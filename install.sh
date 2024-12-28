#!/bin/bash

set -e

# Функции для вывода сообщений
echo_info() {
    echo -e "\033[1;34m$1\033[0m"
}

echo_success() {
    echo -e "\033[0;32m$1\033[0m"
}

echo_error() {
    echo -e "\033[0;31m$1\033[0m" >&2
}

# Проверка запуска от root
if [ "$(id -u)" != "0" ]; then
    echo_error "Please run this script with sudo."
    exit 1
fi

GITHUB_USER="yndmitry"
GITHUB_REPO="wf-publish"
BRANCH="master" # Или другая ветка
INSTALL_DIR="/usr/local/share/wf-publish"
BIN_PATH="/usr/local/bin/wf-publish"
TMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

OS="$(uname)"
ARCH="$(uname -m)"

case "$OS" in
    Linux)
        PLATFORM="linux"
        ;;
    Darwin)
        PLATFORM="macos"
        ;;
    *)
        echo_error "Unsupported OS: $OS"
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64 | amd64)
        ARCH="amd64"
        ;;
    arm64 | aarch64)
        ARCH="arm64"
        ;;
    *)
        echo_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo_info "Downloading a repository from GitHub..."

# URL для скачивания архива репозитория
TARBALL_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/heads/${BRANCH}.tar.gz"

echo_info "Downloading the archive: $TARBALL_URL"
curl -L "$TARBALL_URL" -o "$TMP_DIR/repo.tar.gz"

echo_info "Unpacking the archive..."
tar -xzf "$TMP_DIR/repo.tar.gz" -C "$TMP_DIR"

# Определение распакованной директории
EXTRACTED_DIR="$TMP_DIR/${GITHUB_REPO}-${BRANCH}"

if [ ! -d "$EXTRACTED_DIR/main.dist" ]; then
    echo_error "The main.dist folder is not found in the repository."
    exit 1
fi

if [ ! -f "$EXTRACTED_DIR/main.dist/main.bin" ]; then
    echo_error "The main.bin file is not found in the main.dist folder."
    exit 1
fi

echo_info "Installing the main.dist folder in $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp -r "$EXTRACTED_DIR/main.dist" "$INSTALL_DIR/"

echo_info "Installing main.bin in $BIN_PATH..."
cp "$INSTALL_DIR/main.dist/main.bin" "$BIN_PATH"
chmod +x "$BIN_PATH"

# ln -sf "$BIN_PATH" /usr/local/bin/wf-publish

echo_success "The installation is complete. You can now use 'wf-publish'."
echo_info "To run it, use the command: wf-publish inside the project folder"
