#!/bin/bash

set -euo pipefail

REPO_URL="https://github.com/ryanmwright/restic-backups.git"
INSTALL_DIR="/opt/restic-backup"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root!"
    exit 1
fi

get_strict_input() {
  local prompt="$1"
  local input

  while true; do
    read -rp "$prompt" input < /dev/tty
    input="${input,,}"  # Lowercase

    if [[ "$input" =~ ^[a-z0-9_-]+$ ]]; then
      break
    else
      echo "Input must only contain letters, numbers, underscores, or hyphens." >&2
    fi
  done

  printf '%s' "$input"
}

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
        read -p "Do you want to update it? [y/N] " update_choice < /dev/tty
        if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
            echo "Skipping update of $file."
            secure_file "$file"
            return
        fi
    fi

    read -s -p "$prompt: " secret < /dev/tty
    echo
    echo "$secret" > "$file"
    secure_file "$file"
    echo "$file updated."
}

prompt_http_credentials() {
    local creds_file="$1"

    if [[ -f "$creds_file" ]]; then
        echo "$creds_file already exists."
        read -p "Do you want to update it? [y/N] " update_choice < /dev/tty
        if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
            echo "Skipping update of $creds_file."
            secure_file "$creds_file"
            return
        fi
    fi

    read -p "Enter HTTP Basic Auth username: " http_user < /dev/tty
    read -s -p "Enter HTTP Basic Auth password: " http_pass < /dev/tty
    echo
    echo "${http_user}:${http_pass}" > "$creds_file"
    secure_file "$creds_file"
    echo "$creds_file updated."
}

create_service_unit() {
    local job_name="$1"
    local service_name="$2"

    cat <<EOF > /etc/systemd/system/$service_name
[Unit]
Description=Restic backup ($job_name)

[Service]
Type=oneshot
ExecStart=/opt/restic-backup/backup.sh $job_name
EOF
    echo "Created systemd service: $service_name"
}

create_timer_unit() {
    local job_name="$1"
    local timer_name="$2"

    read -rp "Enter OnCalendar value for timer (e.g. 'daily', '*-*-* 02:00:00'): " schedule < /dev/tty
    schedule=${schedule:-"daily"}

    cat <<EOF > /etc/systemd/system/$timer_name
[Unit]
Description=Run Restic backup ($job_name) on schedule

[Timer]
OnCalendar=$schedule
Persistent=true

[Install]
WantedBy=timers.target
EOF
    echo "Created systemd timer: $timer_name"
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

job_name=$(get_strict_input "Enter a name for this backup job: ")
job_name=${job_name:-"default"}

service_name="restic-backup-$job_name.service"
timer_name="restic-backup-$job_name.timer"
password_file="/root/.restic_password_$job_name"

create_service_unit "$job_name" "$service_name"
create_timer_unit "$job_name" "$timer_name"
sudo systemctl daemon-reload
sudo systemctl enable --now $timer_name

echo "Configuring the Restic password and HTTP password..."

prompt_and_store_secret "Enter Restic repository password" "$password_file"
prompt_http_credentials "/root/.restic_http_credentials_$job_name"
cp /opt/restic-backup/restic-env /usr/local/bin/restic-env

echo "Backup scripts installed and scheduled. Make sure to put your configuration under /etc/restic-backup/$job_name!"
