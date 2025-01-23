#!/bin/bash
set -eo pipefail

# Конфигурация
REPO_OWNER="yndmitry"
REPO_NAME="wf-publish"
API_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest"
TEMP_DIR=$(mktemp -d)
GPG_KEY_URL="https://keys.openpgp.org/vks/v1/by-fingerprint/7D2E524716804412E3F49364015F2BF3ED1116E3"

# Определение платформы
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64";;
    aarch64) ARCH="arm64";;
    arm*) ARCH="arm";;
esac

# Функции
cleanup() {
    rm -rf "$TEMP_DIR"
    echo -e "\033[1;33m⚠️ Temporary files cleaned\033[0m"
}

error() {
    echo -e "\033[1;31m❌ $1\033[0m"
    cleanup
    exit 1
}

# Проверка зависимостей
check_deps() {
    for cmd in curl gpg unzip tar; do
        if ! command -v $cmd &> /dev/null; then
            error "Missing required command: $cmd"
        fi
    done
}

# Основная установка
install_app() {
    case $OS in
        darwin)
            sudo mkdir -p /usr/local/share/wf-publish
            sudo cp -R "$TEMP_DIR/main.app" /usr/local/share/wf-publish/
            sudo ln -sf /usr/local/share/wf-publish/main.app/Contents/MacOS/main /usr/local/bin/wf-publish
            ;;
        linux)
            sudo mkdir -p /opt/wf-publish
            sudo tar -xzf "$TEMP_DIR/$ASSET_NAME" -C /opt/wf-publish
            sudo ln -sf /opt/wf-publish/main /usr/local/bin/wf-publish
            ;;
        *)
            error "Unsupported OS: $OS"
            ;;
    esac
}

# Импорт GPG ключа
import_gpg_key() {
    if ! gpg --list-keys "$REPO_OWNER" &> /dev/null; then
        echo -e "\033[1;36m🔑 Importing GPG key...\033[0m"
        curl -sSL "$GPG_KEY_URL" | gpg --import - || error "Failed to import GPG key"
    fi
}

# Главный процесс
main() {
    trap cleanup EXIT
    check_deps
    import_gpg_key

    echo -e "\033[1;34m🔍 Checking latest release...\033[0m"
    response=$(curl -sSL "$API_URL")
    
    # Определение имени ассета
    ASSET_PATTERN="wf-publish-${OS}-${ARCH}.*"
    ASSET_INFO=$(echo "$response" | jq -r ".assets[] | select(.name | test(\"$ASSET_PATTERN\"))")
    [ -z "$ASSET_INFO" ] && error "No matching asset found for $OS-$ARCH"

    ASSET_NAME=$(echo "$ASSET_INFO" | jq -r '.name')
    DOWNLOAD_URL=$(echo "$ASSET_INFO" | jq -r '.browser_download_url')
    SIG_URL="${DOWNLOAD_URL}.sig"

    echo -e "\033[1;35m⬇️ Downloading $ASSET_NAME...\033[0m"
    curl -L "$DOWNLOAD_URL" -o "$TEMP_DIR/$ASSET_NAME"
    curl -L "$SIG_URL" -o "$TEMP_DIR/$ASSET_NAME.sig"

    echo -e "\033[1;32m🔒 Verifying signature...\033[0m"
    gpg --verify "$TEMP_DIR/$ASSET_NAME.sig" "$TEMP_DIR/$ASSET_NAME" || error "Signature verification failed!"

    echo -e "\033[1;33m🚀 Installing...\033[0m"
    install_app

    echo -e "\033[1;32m✅ Successfully installed wf-publish!\033[0m"
    command -v wf-publish && wf-publish --version
}

main