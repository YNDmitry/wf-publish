#!/bin/bash
set -eo pipefail

# Configuration
REPO_OWNER="yndmitry"
REPO_NAME="wf-publish"
API_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest"
TEMP_DIR=$(mktemp -d)
GPG_KEY_URL="https://keys.openpgp.org/vks/v1/by-fingerprint/7D2E524716804412E3F49364015F2BF3ED1116E3"

# Determine Platform
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64";;
    aarch64) ARCH="arm64";;
    arm*) ARCH="arm";;
esac

# Functions
cleanup() {
    rm -rf "$TEMP_DIR"
    echo -e "\033[1;33m⚠️ Temporary files cleaned\033[0m"
}

error() {
    echo -e "\033[1;31m❌ $1\033[0m"
    cleanup
    exit 1
}

# Check Dependencies
check_deps() {
    for cmd in curl gpg unzip tar jq; do
        if ! command -v $cmd &> /dev/null; then
            error "Missing required command: $cmd"
        fi
    done
}

# Install Application
install_app() {
    case $OS in
        darwin)
            echo -e "\033[1;34m📦 Unpacking macOS ZIP...\033[0m"
            unzip "$TEMP_DIR/$ASSET_NAME" -d "$TEMP_DIR"
            sudo mkdir -p /Applications/wf-publish
            sudo cp -R "$TEMP_DIR/main.app" /Applications/wf-publish/
            sudo ln -sf /Applications/wf-publish/main.app/Contents/MacOS/main /usr/local/bin/wf-publish
            ;;
        linux)
            sudo mkdir -p /opt/wf-publish
            sudo tar -xzf "$TEMP_DIR/$ASSET_NAME" -C /opt/wf-publish
            sudo ln -sf /opt/wf-publish/main /usr/local/bin/wf-publish
            ;;
        windows)
            echo "Windows installation is not supported via this script."
            error "Unsupported OS: $OS"
            ;;
        *)
            error "Unsupported OS: $OS"
            ;;
    esac
}

# Import GPG Key
import_gpg_key() {
    if ! gpg --list-keys "$REPO_OWNER" &> /dev/null; then
        echo -e "\033[1;36m🔑 Importing GPG key...\033[0m"
        curl -sSL "$GPG_KEY_URL" | gpg --import - || error "Failed to import GPG key"
    fi
}

# Main Process
main() {
    trap cleanup EXIT
    check_deps
    import_gpg_key

    echo -e "\033[1;34m🔍 Checking latest release...\033[0m"
    response=$(curl -sSL "$API_URL")

    # Determine Asset Name Pattern
    if [ "$OS" = "darwin" ]; then
        ASSET_PATTERN="wf-publish-macos-universal-.*\\.zip$"
    elif [ "$OS" = "linux" ]; then
        ASSET_PATTERN="wf-publish-linux-.*\\.tar\\.gz$"
    else
        error "Unsupported OS: $OS"
    fi

    # Use --arg to pass the pattern to jq
    ASSET_INFO=$(echo "$response" | jq -r --arg pattern "$ASSET_PATTERN" '.assets[] | select(.name | test($pattern))')

    if [ -z "$ASSET_INFO" ]; then
        echo -e "\033[1;31m❌ No matching asset found for $OS-$ARCH\033[0m"
        echo -e "\033[1;34m📦 Available assets:\033[0m"
        echo "$response" | jq -r '.assets[] | .name'
        error "Please ensure that the artifacts are correctly uploaded."
    fi

    ASSET_NAME=$(echo "$ASSET_INFO" | jq -r '.name')
    DOWNLOAD_URL=$(echo "$ASSET_INFO" | jq -r '.browser_download_url')
    SIG_URL="${DOWNLOAD_URL}.asc"

    echo -e "\033[1;35m⬇️ Downloading $ASSET_NAME...\033[0m"
    curl -L "$DOWNLOAD_URL" -o "$TEMP_DIR/$ASSET_NAME"
    curl -L "$SIG_URL" -o "$TEMP_DIR/$ASSET_NAME.asc"

    echo -e "\033[1;32m🔒 Verifying signature...\033[0m"
    gpg --verify "$TEMP_DIR/$ASSET_NAME.asc" "$TEMP_DIR/$ASSET_NAME" || error "Signature verification failed!"

    echo -e "\033[1;33m🚀 Installing...\033[0m"
    install_app

    echo -e "\033[1;32m✅ wf-publish successfully installed!\033[0m"
    echo -e "You can verify the installation by running \`wf-publish --version\`."
}

main
