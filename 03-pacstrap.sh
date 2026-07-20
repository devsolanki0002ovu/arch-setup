#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 03-pacstrap.sh — Base System & Package Installation
# ─────────────────────────────────────────────────────────────────────────────
# Installs all required packages via pacstrap, generates fstab, and verifies
# that critical system files exist in the new root.
#
# Depends on: globals.env, 00-lib.sh, 02-disk.sh (mounted filesystems)
# ─────────────────────────────────────────────────────────────────────────────

set_stage "03-pacstrap"

# ═══════════════════════════════════════════════════════════════════════════════
#  PRE-CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

verify_mount "${GTLTSC_MOUNT_ROOT}" "Root filesystem"
verify_mount "${GTLTSC_MOUNT_ROOT}/boot" "EFI partition"

# ═══════════════════════════════════════════════════════════════════════════════
#  PACSTRAP — INSTALL ALL PACKAGES
# ═══════════════════════════════════════════════════════════════════════════════

log "Installing ${#GTLTSC_ALL_PACKAGES[@]} packages via pacstrap..."
log "This will take a while on a 7200 RPM HDD. Be patient."

# pacstrap with -K initializes an empty pacman keyring in the new root
retry "${GTLTSC_RETRY_COUNT}" "${GTLTSC_RETRY_DELAY}" \
    pacstrap -K "${GTLTSC_MOUNT_ROOT}" "${GTLTSC_ALL_PACKAGES[@]}"

log "Pacstrap complete"

# ═══════════════════════════════════════════════════════════════════════════════
#  GENERATE FSTAB
# ═══════════════════════════════════════════════════════════════════════════════

log "Generating fstab with UUIDs..."
genfstab -U "${GTLTSC_MOUNT_ROOT}" >> "${GTLTSC_MOUNT_ROOT}/etc/fstab" \
    || die "Failed to generate fstab"

# ── Verify fstab ─────────────────────────────────────────────────────────────
verify_file "${GTLTSC_MOUNT_ROOT}/etc/fstab" "fstab"

# Verify fstab contains UUID entries (not device paths)
_fstab_uuid_count=$(grep -c "^UUID=" "${GTLTSC_MOUNT_ROOT}/etc/fstab" || true)
if (( _fstab_uuid_count < 2 )); then
    warn "fstab has fewer than 2 UUID entries (found ${_fstab_uuid_count}). Verifying content..."
    cat "${GTLTSC_MOUNT_ROOT}/etc/fstab" >&2
fi

# Verify fstab references both our UUIDs
_efi_uuid=$(blkid -s UUID -o value "${GTLTSC_EFI_PART}")
_root_uuid=$(blkid -s UUID -o value "${GTLTSC_ROOT_PART}")

if ! grep -q "${_root_uuid}" "${GTLTSC_MOUNT_ROOT}/etc/fstab"; then
    die "fstab does not contain root partition UUID: ${_root_uuid}"
fi
if ! grep -q "${_efi_uuid}" "${GTLTSC_MOUNT_ROOT}/etc/fstab"; then
    die "fstab does not contain EFI partition UUID: ${_efi_uuid}"
fi

log "fstab verified with UUID entries for both partitions"

# ── Add noatime to root entry if not already present ─────────────────────────
# genfstab should pick up the mount options, but let's ensure
if ! grep "${_root_uuid}" "${GTLTSC_MOUNT_ROOT}/etc/fstab" | grep -q "noatime"; then
    log "Adding noatime to root fstab entry..."
    sed -i "/${_root_uuid}/s/relatime/noatime/" "${GTLTSC_MOUNT_ROOT}/etc/fstab" 2>/dev/null || true
    sed -i "/${_root_uuid}/s/defaults/defaults,noatime/" "${GTLTSC_MOUNT_ROOT}/etc/fstab" 2>/dev/null || true
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  CRITICAL FILE VERIFICATION
# ═══════════════════════════════════════════════════════════════════════════════

log "Verifying critical system files..."

# Kernel
verify_file "${GTLTSC_MOUNT_ROOT}/boot/vmlinuz-linux-lts" "LTS kernel image"

# Initramfs
verify_file "${GTLTSC_MOUNT_ROOT}/boot/initramfs-linux-lts.img" "LTS initramfs"

# Bash
verify_file "${GTLTSC_MOUNT_ROOT}/usr/bin/bash" "bash shell"

# Systemd
verify_file "${GTLTSC_MOUNT_ROOT}/usr/lib/systemd/systemd" "systemd init"

# Pacman
verify_file "${GTLTSC_MOUNT_ROOT}/usr/bin/pacman" "pacman"

# GRUB
verify_file "${GTLTSC_MOUNT_ROOT}/usr/bin/grub-install" "grub-install"
verify_file "${GTLTSC_MOUNT_ROOT}/usr/bin/grub-mkconfig" "grub-mkconfig"

# Intel microcode
verify_file "${GTLTSC_MOUNT_ROOT}/boot/intel-ucode.img" "Intel microcode"

# Plymouth
verify_file "${GTLTSC_MOUNT_ROOT}/usr/bin/plymouth" "plymouth"

# xmlstarlet (needed by 05-gui.sh)
verify_file "${GTLTSC_MOUNT_ROOT}/usr/bin/xmlstarlet" "xmlstarlet"

# ═══════════════════════════════════════════════════════════════════════════════
#  PACKAGE SPOT-CHECK
# ═══════════════════════════════════════════════════════════════════════════════

log "Spot-checking critical packages in chroot..."

_spot_check_packages=(
    linux-lts
    grub
    networkmanager
    sddm
    lxqt-session
    openbox
    firefox
    pipewire
    wireplumber
    plymouth
    earlyoom
    materia-gtk-theme
    papirus-icon-theme
    qt6ct
    xmlstarlet
)

for pkg in "${_spot_check_packages[@]}"; do
    verify_package "${pkg}" "${GTLTSC_MOUNT_ROOT}"
done

log "All critical packages verified in chroot"

# ═══════════════════════════════════════════════════════════════════════════════
#  COPY GLOBALS INTO CHROOT
# ═══════════════════════════════════════════════════════════════════════════════

# Copy globals.env into the new root for chroot scripts to source
log "Copying globals.env into chroot..."
ensure_dir "${GTLTSC_MOUNT_ROOT}/tmp"
cp "${BASH_SOURCE[0]%/*}/globals.env" "${GTLTSC_MOUNT_ROOT}/tmp/gtltsc-globals.env" \
    || die "Failed to copy globals.env into chroot"

# Write current runtime values (collected interactively) into the chroot copy
# Use printf '%q' to safely escape all values
{
    printf 'GTLTSC_HOSTNAME=%q\n' "${GTLTSC_HOSTNAME}"
    printf 'GTLTSC_USERNAME=%q\n' "${GTLTSC_USERNAME}"
    printf 'GTLTSC_USER_DISPLAY=%q\n' "${GTLTSC_USER_DISPLAY}"
    printf 'GTLTSC_USER_PASSWORD=%q\n' "${GTLTSC_USER_PASSWORD}"
    printf 'GTLTSC_ROOT_PASSWORD=%q\n' "${GTLTSC_ROOT_PASSWORD}"
    printf 'GTLTSC_LOCALE=%q\n' "${GTLTSC_LOCALE}"
    printf 'GTLTSC_KEYMAP=%q\n' "${GTLTSC_KEYMAP}"
    printf 'GTLTSC_TIMEZONE=%q\n' "${GTLTSC_TIMEZONE}"
    printf 'GTLTSC_TARGET_DISK=%q\n' "${GTLTSC_TARGET_DISK}"
    printf 'GTLTSC_EFI_PART=%q\n' "${GTLTSC_EFI_PART}"
    printf 'GTLTSC_ROOT_PART=%q\n' "${GTLTSC_ROOT_PART}"
} >> "${GTLTSC_MOUNT_ROOT}/tmp/gtltsc-globals.env"

log "Runtime values persisted to chroot"
log "Pacstrap stage complete ✓"
