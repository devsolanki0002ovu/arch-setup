#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 02-disk.sh — Partitioning, Formatting, and Mounting
# ─────────────────────────────────────────────────────────────────────────────
# Creates GPT partition table: 512M EFI + remainder ext4 root.
# Uses dynamic partition discovery — never hardcodes partition names.
# Verifies every step: partition existence, format, mount.
#
# Depends on: globals.env, 00-lib.sh, 01-preflight.sh (for GTLTSC_TARGET_DISK)
# ─────────────────────────────────────────────────────────────────────────────

set_stage "02-disk"

# ═══════════════════════════════════════════════════════════════════════════════
#  SAFETY CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

log "Verifying target disk: ${GTLTSC_TARGET_DISK}"

if [[ ! -b "${GTLTSC_TARGET_DISK}" ]]; then
    die "Target disk is not a block device: ${GTLTSC_TARGET_DISK}"
fi

# Ensure nothing on this disk is currently mounted
log "Checking for active mounts on ${GTLTSC_TARGET_DISK}..."
if findmnt -rn -S "${GTLTSC_TARGET_DISK}" &>/dev/null || \
   lsblk -nrpo NAME "${GTLTSC_TARGET_DISK}" | while read -r part; do
       findmnt -rn -S "${part}" &>/dev/null && exit 0
   done; then
    warn "Active mounts detected on ${GTLTSC_TARGET_DISK}, attempting to unmount..."
    # Unmount all partitions on this disk, deepest first
    lsblk -nrpo NAME "${GTLTSC_TARGET_DISK}" | sort -r | while read -r part; do
        if findmnt -rn -S "${part}" &>/dev/null; then
            local_mp=$(findmnt -rn -o TARGET -S "${part}" 2>/dev/null || true)
            log "Unmounting: ${part} (${local_mp})"
            umount -R "${local_mp}" 2>/dev/null || umount -l "${local_mp}" 2>/dev/null || true
        fi
    done
    # Disable swap on any partition of this disk
    lsblk -nrpo NAME "${GTLTSC_TARGET_DISK}" | while read -r part; do
        swapoff "${part}" 2>/dev/null || true
    done
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  WIPE & PARTITION
# ═══════════════════════════════════════════════════════════════════════════════

log "Wiping partition table on ${GTLTSC_TARGET_DISK}..."
sgdisk --zap-all "${GTLTSC_TARGET_DISK}" || die "Failed to wipe partition table"
log "Partition table wiped"

log "Creating GPT partition table..."

# Partition 1: EFI System Partition (512M, type EF00)
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "${GTLTSC_TARGET_DISK}" \
    || die "Failed to create EFI partition"

# Partition 2: Linux root (remainder, type 8300)
sgdisk -n 2:0:0 -t 2:8300 -c 2:"ROOT" "${GTLTSC_TARGET_DISK}" \
    || die "Failed to create root partition"

log "Partition table created"

# ═══════════════════════════════════════════════════════════════════════════════
#  PARTITION SYNCHRONIZATION
# ═══════════════════════════════════════════════════════════════════════════════
# After partitioning, the kernel may not immediately see the new partitions.
# We use partprobe + udevadm settle + polling to wait for readiness.

log "Synchronizing partition table with kernel..."
partprobe "${GTLTSC_TARGET_DISK}" 2>/dev/null || true
udevadm settle --timeout=10 || warn "udevadm settle timed out (non-fatal)"

# Poll for partitions to appear
log "Waiting for partitions to appear (timeout: ${GTLTSC_PARTITION_WAIT_TIMEOUT}s)..."
_wait_elapsed=0
while (( _wait_elapsed < GTLTSC_PARTITION_WAIT_TIMEOUT )); do
    # Count child partitions (exclude the disk itself)
    _part_count=$(lsblk -nrpo NAME "${GTLTSC_TARGET_DISK}" | grep -v "^${GTLTSC_TARGET_DISK}$" | wc -l)
    if (( _part_count >= 2 )); then
        log "Both partitions detected after ${_wait_elapsed}s"
        break
    fi
    sleep "${GTLTSC_PARTITION_POLL_INTERVAL}"
    (( _wait_elapsed += GTLTSC_PARTITION_POLL_INTERVAL ))
done

if (( _part_count < 2 )); then
    die "Timeout: only ${_part_count}/2 partitions appeared after ${GTLTSC_PARTITION_WAIT_TIMEOUT}s on ${GTLTSC_TARGET_DISK}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  DYNAMIC PARTITION DISCOVERY
# ═══════════════════════════════════════════════════════════════════════════════
# Never assume partition naming (sda1, nvme0n1p1, etc.)
# Instead, read from lsblk and use positional ordering.

log "Discovering partition paths..."
mapfile -t _disk_parts < <(lsblk -nrpo NAME "${GTLTSC_TARGET_DISK}" | grep -v "^${GTLTSC_TARGET_DISK}$" | sort)

if (( ${#_disk_parts[@]} < 2 )); then
    die "Expected 2 partitions, found ${#_disk_parts[@]} on ${GTLTSC_TARGET_DISK}"
fi

GTLTSC_EFI_PART="${_disk_parts[0]}"
GTLTSC_ROOT_PART="${_disk_parts[1]}"

log "EFI partition:  ${GTLTSC_EFI_PART}"
log "Root partition: ${GTLTSC_ROOT_PART}"

# Verify both are block devices
if [[ ! -b "${GTLTSC_EFI_PART}" ]]; then
    die "EFI partition is not a block device: ${GTLTSC_EFI_PART}"
fi
if [[ ! -b "${GTLTSC_ROOT_PART}" ]]; then
    die "Root partition is not a block device: ${GTLTSC_ROOT_PART}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  FORMAT PARTITIONS
# ═══════════════════════════════════════════════════════════════════════════════

log "Formatting EFI partition (FAT32): ${GTLTSC_EFI_PART}"
mkfs.fat -F 32 "${GTLTSC_EFI_PART}" || die "Failed to format EFI partition"
log "EFI partition formatted"

log "Formatting root partition (ext4): ${GTLTSC_ROOT_PART}"
mkfs.ext4 -F "${GTLTSC_ROOT_PART}" || die "Failed to format root partition"
log "Root partition formatted"

# Verify filesystem types
_efi_fstype=$(lsblk -nro FSTYPE "${GTLTSC_EFI_PART}")
_root_fstype=$(lsblk -nro FSTYPE "${GTLTSC_ROOT_PART}")

if [[ "${_efi_fstype}" != "vfat" ]]; then
    die "EFI partition has wrong filesystem type: expected vfat, got ${_efi_fstype}"
fi
if [[ "${_root_fstype}" != "ext4" ]]; then
    die "Root partition has wrong filesystem type: expected ext4, got ${_root_fstype}"
fi

log "Filesystem types verified (vfat + ext4)"

# ═══════════════════════════════════════════════════════════════════════════════
#  MOUNT PARTITIONS
# ═══════════════════════════════════════════════════════════════════════════════

log "Mounting root partition to ${GTLTSC_MOUNT_ROOT}..."
ensure_dir "${GTLTSC_MOUNT_ROOT}"
mount -o noatime "${GTLTSC_ROOT_PART}" "${GTLTSC_MOUNT_ROOT}" \
    || die "Failed to mount root partition"
verify_mount "${GTLTSC_MOUNT_ROOT}" "Root filesystem"

log "Mounting EFI partition to ${GTLTSC_MOUNT_ROOT}/boot..."
ensure_dir "${GTLTSC_MOUNT_ROOT}/boot"
mount "${GTLTSC_EFI_PART}" "${GTLTSC_MOUNT_ROOT}/boot" \
    || die "Failed to mount EFI partition"
verify_mount "${GTLTSC_MOUNT_ROOT}/boot" "EFI System Partition"

# ═══════════════════════════════════════════════════════════════════════════════
#  FINAL VERIFICATION
# ═══════════════════════════════════════════════════════════════════════════════

log "Disk layout verification:"
log "  $(lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "${GTLTSC_TARGET_DISK}" | head -5)"

# Verify UUIDs are available (needed for fstab later)
_efi_uuid=$(blkid -s UUID -o value "${GTLTSC_EFI_PART}")
_root_uuid=$(blkid -s UUID -o value "${GTLTSC_ROOT_PART}")

if [[ -z "${_efi_uuid}" || -z "${_root_uuid}" ]]; then
    die "Failed to read UUIDs from partitions"
fi

log "  EFI  UUID: ${_efi_uuid}"
log "  Root UUID: ${_root_uuid}"
log "Disk stage complete ✓"
