#!/bin/bash

set -euo pipefail

REPO_URL="https://github.com/ryanmwright/restic-backups.git"
INSTALL_DIR="/opt/restic-backup"

if [ -d "$INSTALL_DIR/.git" ]; then
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

sudo cp "$INSTALL_DIR/backup.service" /etc/systemd/system/
sudo cp "$INSTALL_DIR/backup.timer" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now backup.timer

echo "Backup scripts installed and scheduled. Make sure to put your restic password under /root/.resticpassword and specify your configuration under /etc/restic-backup!"
