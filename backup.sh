#!/bin/bash

set -euo pipefail

# Defaults
JOB_NAME="${1:-default}"
export RESTIC_PASSWORD_FILE="/root/.restic_password_$JOB_NAME"
RESTIC_HTTP_CREDENTIALS="$(cat /root/.restic_http_credentials_$JOB_NAME)"
EXCLUDE_FILE="/etc/restic-backup/$JOB_NAME/excludes.txt"
CONFIG_FILE="/etc/restic-backup/$JOB_NAME/backup.conf"

EXCLUDE_FILES=("$EXCLUDE_FILE")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

IEXCLUDE_PARAMS=()
for exclude in "${BACKUP_EXCLUDES[@]}"; do
    IEXCLUDE_PARAMS+=(--iexclude="$exclude")
done

EXCLUDEFILE_PARAMS=()
for f in "${EXCLUDE_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    EXCLUDEFILE_PARAMS+=(--exclude-file="$f")
  fi
done

if [[ -n "$HOST_MACHINE" ]]; then
    RESTIC_HOSTNAME_PARAM=(--hostname "$HOST_MACHINE")
fi

source $SCRIPT_DIR/snapshot_vm.sh

on_error() {
    echo "Error on line $1. Exit code: $2"
    # TODO: Notify/raise an alert on error
}

# Ensure cleanup happens even on failure
trap 'on_error $LINENO $?' ERR
trap cleanup_vms EXIT

# Snap VMs first
for vm_entry in "${VM_LIST[@]}"; do
    IFS=':' read -r vmname vmhost <<< "$vm_entry"
    snapshot_vm "$vmname" "$vmhost"
done

# Perform the backup (combine folders + VM files)
restic -r $RESTIC_REPOSITORY backup \
    "${BACKUP_PATHS[@]}" \
    "${VM_BACKUP_PATHS[@]}" \
    "${IEXCLUDE_PARAMS[@]}" \
    "${EXCLUDEFILE_PARAMS[@]}" \
    "${RESTIC_HOSTNAME_ARG[@]}" \
    --tag auto \
    --tag "$HOST_MACHINE-current" \
    --verbose --exclude-caches --one-file-system --compression max

echo "Backup completed"