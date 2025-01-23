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
    echo -e "\033[1;33m⚠️ Временные файлы очищены\033[0m"
}

error() {
    echo -e "\033[1;31m❌ $1\033[0m"
    cleanup
    exit 1
}

# Проверка зависимостей
check_deps() {
    for cmd in curl gpg unzip tar jq; do
        if ! command -v $cmd &> /dev/null; then
            error "Отсутствует необходимая команда: $cmd"
        fi
    done
}

# Основная установка
install_app() {
    case $OS in
        darwin)
            echo -e "\033[1;34m📦 Распаковка macOS ZIP...\033[0m"
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
        *)
            error "Не поддерживаемая ОС: $OS"
            ;;
    esac
}

# Импорт GPG ключа
import_gpg_key() {
    if ! gpg --list-keys "$REPO_OWNER" &> /dev/null; then
        echo -e "\033[1;36m🔑 Импортирование GPG ключа...\033[0m"
        curl -sSL "$GPG_KEY_URL" | gpg --import - || error "Не удалось импортировать GPG ключ"
    fi
}

# Главный процесс
main() {
    trap cleanup EXIT
    check_deps
    import_gpg_key

    echo -e "\033[1;34m🔍 Проверка последнего релиза...\033[0m"
    response=$(curl -sSL "$API_URL")

    # Определение имени ассета
    if [ "$OS" = "darwin" ]; then
        ASSET_PATTERN="wf-publish-macos-universal-.*\.zip$"
    elif [ "$OS" = "linux" ]; then
        ASSET_PATTERN="wf-publish-linux-.*\.tar\.gz$"
    else
        error "Не поддерживаемая ОС: $OS"
    fi

    ASSET_INFO=$(echo "$response" | jq -r ".assets[] | select(.name | test(\"$ASSET_PATTERN\"))")
    [ -z "$ASSET_INFO" ] && error "Соответствующий ассет не найден для $OS"

    ASSET_NAME=$(echo "$ASSET_INFO" | jq -r '.name')
    DOWNLOAD_URL=$(echo "$ASSET_INFO" | jq -r '.browser_download_url')
    SIG_URL="${DOWNLOAD_URL}.asc"

    echo -e "\033[1;35m⬇️ Загрузка $ASSET_NAME...\033[0m"
    curl -L "$DOWNLOAD_URL" -o "$TEMP_DIR/$ASSET_NAME"
    curl -L "$SIG_URL" -o "$TEMP_DIR/$ASSET_NAME.asc"

    echo -e "\033[1;32m🔒 Проверка подписи...\033[0m"
    gpg --verify "$TEMP_DIR/$ASSET_NAME.asc" "$TEMP_DIR/$ASSET_NAME" || error "Проверка подписи не удалась!"

    echo -e "\033[1;33m🚀 Установка...\033[0m"
    install_app

    echo -e "\033[1;32m✅ wf-publish успешно установлен!\033[0m"
    command -v wf-publish && wf-publish --version
}

main
