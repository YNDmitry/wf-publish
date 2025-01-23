#!/bin/bash
set -eo pipefail

REPO_OWNER="yndmitry"
REPO_NAME="wf-publish-public"
API_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest"

# Получаем последний релиз
response=$(curl -sSL "$API_URL")
download_url=$(echo "$response" | grep -E 'browser_download_url.*release.zip' | cut -d'"' -f4)
sig_url=$(echo "$response" | grep -E 'browser_download_url.*build.sig' | cut -d'"' -f4)

# Скачиваем файлы
temp_dir=$(mktemp -d)
curl -L "$download_url" -o "$temp_dir/release.zip"
curl -L "$sig_url" -o "$temp_dir/build.sig"

# Проверяем подпись
gpg --verify "$temp_dir/build.sig" "$temp_dir/release.zip" || {
    echo -e "\033[1;31m❌ Signature verification failed!\033[0m"
    exit 1
}

# Установка
unzip "$temp_dir/release.zip" -d "$temp_dir"
sudo mkdir -p /usr/local/share/wf-publish
sudo cp -R "$temp_dir/main.app" /usr/local/share/wf-publish/
sudo ln -sf /usr/local/share/wf-publish/main.app/Contents/MacOS/main /usr/local/bin/wf-publish

echo -e "\033[1;32m✅ Successfully installed!\033[0m"