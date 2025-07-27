#!/bin/bash

set -euo pipefail

REPO_URL="https://github.com/ryanmwright/restic-backups.git"
INSTALL_DIR="/opt/restic-backup"
RESTIC_PASSWORD_FILE="/root/.resticpassword"
HTTP_CREDENTIALS_FILE="/root/.restic_http_credentials"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root!"
    exit 1
fi

secure_file() {
    local file="$1"
    echo "Ensuring permissions on $file..."
    chown root:root "$file"
    chmod 600 "$file"
}

prompt_and_store_secret() {
    local prompt="$1"
    local file="$2"

    if [[ -f "$file" ]]; then
        echo "$file already exists."
        read -p "Do you want to update it? [y/N] " update_choice
        if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
            echo "Skipping update of $file."
            secure_file "$file"
            return
        fi
    fi

    read -s -p "$prompt: " secret
    echo
    echo "$secret" > "$file"
    secure_file "$file"
    echo "$file updated."
}

prompt_http_credentials() {
    if [[ -f "$HTTP_CREDENTIALS_FILE" ]]; then
        echo "$HTTP_CREDENTIALS_FILE already exists."
        read -p "Do you want to update it? [y/N] " update_choice
        if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
            echo "Skipping update of $HTTP_CREDENTIALS_FILE."
            secure_file "$HTTP_CREDENTIALS_FILE"
            return
        fi
    fi

    read -p "Enter HTTP Basic Auth username: " http_user
    read -s -p "Enter HTTP Basic Auth password: " http_pass
    echo
    echo "${http_user}:${http_pass}" > "$HTTP_CREDENTIALS_FILE"
    secure_file "$HTTP_CREDENTIALS_FILE"
    echo "$HTTP_CREDENTIALS_FILE updated."
}

if [ -d "$INSTALL_DIR/.git" ]; then
    git -C "$INSTALL_DIR" reset --hard
    git -C "$INSTALL_DIR" pull
else
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

if ! command -v restic &> /dev/null; then
    echo "Installing restic..."
    sudo dnf install -y restic || sudo apt-get install -y restic
fi

sudo chown -R root:root "$INSTALL_DIR"
sudo chmod +x "$INSTALL_DIR"/*.sh

sudo cp "$INSTALL_DIR/restic-backup.service" /etc/systemd/system/
sudo cp "$INSTALL_DIR/restic-backup.timer" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now restic-backup.timer

echo "Configuring the Restic password and HTTP password..."

prompt_and_store_secret "Enter Restic repository password" "$RESTIC_PASSWORD_FILE"
prompt_http_credentials

echo "Backup scripts installed and scheduled. Make sure to put your configuration under /etc/restic-backup!"
