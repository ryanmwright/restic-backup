#!/bin/bash

set -euo pipefail

SNAPSHOT_PATH="/tmp/backup/libvirt/snapshots"
CONFIG_XML_TARGET_PATH="/var/lib/libvirt/configbackup"
DISK_PATH="/var/lib/libvirt/images"
VM_BACKUP_PATHS=()

declare -A CLEANUP_PATHS

snapshot_vm() {
    VM_NAME="$1"
    VM_HOST="$2"

    echo "Snapshotting VM $VM_NAME"

    mkdir -p "$SNAPSHOT_PATH/$VM_NAME" "$CONFIG_XML_TARGET_PATH"

    VM_DISK="$DISK_PATH/$VM_NAME.qcow2"
    SNAPSHOT_FILE="$SNAPSHOT_PATH/$VM_NAME/$VM_NAME-state.qcow2"
    CONFIG_FILE="$CONFIG_XML_TARGET_PATH/$VM_NAME.xml"

    virsh dumpxml "$VM_NAME" > "$CONFIG_FILE"

    virsh snapshot-create-as --domain "$VM_NAME" "$VM_NAME-state" \
        --diskspec vda,file="$SNAPSHOT_FILE" \
        --disk-only --atomic --quiesce --no-metadata

    VM_BACKUP_PATHS+=("$VM_DISK" "$CONFIG_FILE")

    CLEANUP_PATHS["$VM_NAME"]="$SNAPSHOT_FILE"
}

cleanup_vms() {
    for VM_NAME in "${!CLEANUP_PATHS[@]}"; do
        echo "Block committing and cleaning up VM $VM_NAME"
        virsh blockcommit "$VM_NAME" vda --active --verbose --pivot
        rm -f "${CLEANUP_PATHS[$VM_NAME]}"
    done
}