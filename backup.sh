#!/bin/bash

set -euo pipefail

# Defaults
export RESTIC_PASSWORD_FILE="/root/.resticpassword"
EXCLUDE_FILES=("/etc/restic-backup/excludes.txt")

source /etc/restic-backup/backup.conf

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

source ./snapshot_vm.sh

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
echo restic -r $RESTIC_REPOSITORY backup \
    "${BACKUP_PATHS[@]}" \
    "${VM_BACKUP_PATHS[@]}" \
    "${IEXCLUDE_PARAMS[@]}" \
    "${EXCLUDEFILE_PARAMS[@]}" \
    --tag auto \
    --tag "$HOST_MACHINE-current" \
    --verbose --exclude-caches --compression max
