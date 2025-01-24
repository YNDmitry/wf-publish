#!/bin/bash
set -eo pipefail

# Configuration
REPO_OWNER="yndmitry"
REPO_NAME="wf-publish"
API_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest"
TEMP_DIR=$(mktemp -d)

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
    echo -e "\033[1;33m⚠️ Temporary files cleaned up\033[0m"
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
            echo -e "\033[1;34m📦 Extracting macOS ZIP...\033[0m"
            unzip "$TEMP_DIR/$ASSET_NAME" -d "$TEMP_DIR"
            
            # Installation paths
            INSTALL_DIR="/usr/local/share/wf-publish"
            BIN_LINK="/usr/local/bin/wf-publish"
            
            # Create directory structure
            echo -e "\033[1;33m🛠 Creating directory structure...\033[0m"
            sudo mkdir -p "$INSTALL_DIR"
            
            # Copy the 'main.dist' directory to the installation directory
            echo -e "\033[1;32m⚙️ Installing application...\033[0m"
            sudo cp -R "$TEMP_DIR/main.dist" "$INSTALL_DIR/"
            
            # Create a symbolic link to the executable
            echo -e "\033[1;36m🔗 Creating symbolic link...\033[0m"
            sudo ln -sf "$INSTALL_DIR/main.dist/main.bin" "$BIN_LINK"
            
            # Adjust permissions
            echo -e "\033[1;35m🔒 Setting permissions...\033[0m"
            sudo chmod -R 755 "$INSTALL_DIR"
            ;;
        # ... (rest of the script remains unchanged)
    esac
}


# Main Process
main() {
    trap cleanup EXIT
    check_deps

    echo -e "\033[1;34m🔍 Checking latest release...\033[0m"
    response=$(curl -sSL "$API_URL")

    # Determine Asset Name Pattern
    if [ "$OS" = "darwin" ]; then
        ASSET_PATTERN="wf-publish-macos-universal.zip$"
    elif [ "$OS" = "linux" ]; then
        ASSET_PATTERN="wf-publish-linux-.*\\.tar\\.gz$"
    else
        error "Unsupported OS: $OS"
    fi

    # Use --arg to pass the pattern to jq
    ASSET_INFO=$(echo "$response" | jq -r --arg pattern "$ASSET_PATTERN" '.assets[] | select(.name | test($pattern))')

    if [ -z "$ASSET_INFO" ]; then
        echo -e "\033[1;31m❌ No matching artifacts found for $OS-$ARCH\033[0m"
        echo -e "\033[1;34m📦 Available artifacts:\033[0m"
        echo "$response" | jq -r '.assets[] | .name'
        error "Please ensure artifacts are uploaded correctly."
    fi

    ASSET_NAME=$(echo "$ASSET_INFO" | jq -r '.name')
    DOWNLOAD_URL=$(echo "$ASSET_INFO" | jq -r '.browser_download_url')
    SIG_URL="${DOWNLOAD_URL}.asc"

    echo -e "\033[1;35m⬇️ Downloading $ASSET_NAME...\033[0m"
    curl -L "$DOWNLOAD_URL" -o "$TEMP_DIR/$ASSET_NAME"
    curl -L "$SIG_URL" -o "$TEMP_DIR/$ASSET_NAME.asc"

    echo -e "\033[1;33m🚀 Installing...\033[0m"
    install_app

    echo -e "\033[1;32m✅ wf-publish installed successfully!\033[0m"
    echo -e "Verify the installation by running \`wf-publish --version\`."
}

main
