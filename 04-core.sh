#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 04-core.sh — System Configuration (runs via arch-chroot)
# ─────────────────────────────────────────────────────────────────────────────
# Configures locale, timezone, hostname, users, bootloader, performance
# tuning, and system services inside the chroot.
#
# Depends on: globals.env, 00-lib.sh, 03-pacstrap.sh (installed packages)
# ─────────────────────────────────────────────────────────────────────────────

set_stage "04-core"

_ROOT="${GTLTSC_MOUNT_ROOT}"

# Source runtime globals from chroot copy
if [[ -f "${_ROOT}/tmp/gtltsc-globals.env" ]]; then
    # shellcheck source=/dev/null
    source "${_ROOT}/tmp/gtltsc-globals.env"
fi

verify_mount "${_ROOT}" "Root filesystem"
verify_mount "${_ROOT}/boot" "EFI partition"

# ═══════════════════════════════════════════════════════════════════════════════
#  LOCALE
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring locale: ${GTLTSC_LOCALE}"

# Uncomment the target locale in locale.gen (idempotent)
_locale_line="${GTLTSC_LOCALE} UTF-8"
if ! grep -q "^${_locale_line}" "${_ROOT}/etc/locale.gen"; then
    sed -i "s/^#${_locale_line}/${_locale_line}/" "${_ROOT}/etc/locale.gen" \
        || die "Failed to uncomment locale in locale.gen"
fi

# Also ensure en_US.UTF-8 is always available as fallback
if ! grep -q "^en_US.UTF-8 UTF-8" "${_ROOT}/etc/locale.gen"; then
    sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "${_ROOT}/etc/locale.gen" \
        || die "Failed to uncomment en_US.UTF-8 in locale.gen"
fi

safe_chroot "locale-gen" || die "locale-gen failed"

safe_write "${_ROOT}/etc/locale.conf" "LANG=${GTLTSC_LOCALE}"
safe_write "${_ROOT}/etc/vconsole.conf" "KEYMAP=${GTLTSC_KEYMAP}"

log "Locale configured ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  TIMEZONE
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring timezone: ${GTLTSC_TIMEZONE}"

safe_chroot "ln -sf /usr/share/zoneinfo/${GTLTSC_TIMEZONE} /etc/localtime" \
    || die "Failed to set timezone"
safe_chroot "hwclock --systohc" \
    || die "hwclock --systohc failed"

verify_file "${_ROOT}/etc/localtime" "Timezone symlink"
log "Timezone configured ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  HOSTNAME
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring hostname: ${GTLTSC_HOSTNAME}"

safe_write "${_ROOT}/etc/hostname" "${GTLTSC_HOSTNAME}"

safe_write_heredoc "${_ROOT}/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${GTLTSC_HOSTNAME}.localdomain ${GTLTSC_HOSTNAME}
EOF

log "Hostname configured ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  USERS & SUDO
# ═══════════════════════════════════════════════════════════════════════════════

log "Creating user: ${GTLTSC_USERNAME}"

# Create user (idempotent — skip if exists)
if safe_chroot "id ${GTLTSC_USERNAME}" &>/dev/null; then
    log "User ${GTLTSC_USERNAME} already exists, skipping creation"
else
    safe_chroot "useradd -m -G wheel,video,audio,storage,optical,input -s /bin/bash ${GTLTSC_USERNAME}" \
        || die "Failed to create user: ${GTLTSC_USERNAME}"
fi

# Set display name (GECOS field)
safe_chroot "chfn -f '${GTLTSC_USER_DISPLAY}' ${GTLTSC_USERNAME}" \
    || warn "Failed to set display name (non-fatal)"

# Set passwords using chpasswd — avoids heredoc injection issues
printf '%s:%s\n' "${GTLTSC_USERNAME}" "${GTLTSC_USER_PASSWORD}" \
    | safe_chroot "chpasswd" \
    || die "Failed to set user password"

printf '%s:%s\n' "root" "${GTLTSC_ROOT_PASSWORD}" \
    | safe_chroot "chpasswd" \
    || die "Failed to set root password"

# Configure sudo for wheel group (idempotent)
_sudoers_wheel="${_ROOT}/etc/sudoers.d/10-wheel"
safe_write "${_sudoers_wheel}" "%wheel ALL=(ALL:ALL) ALL" "0440"

# Validate sudoers syntax
safe_chroot "visudo -cf /etc/sudoers.d/10-wheel" \
    || die "Sudoers validation failed"

# Verify user creation
safe_chroot "id ${GTLTSC_USERNAME}" || die "User verification failed"
log "User ${GTLTSC_USERNAME} configured with sudo ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  MKINITCPIO — INITRAMFS WITH PLYMOUTH
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring mkinitcpio hooks..."

# Backup original
cp "${_ROOT}/etc/mkinitcpio.conf" "${_ROOT}/etc/mkinitcpio.conf.bak" 2>/dev/null || true

# Write the hooks line (idempotent — replace existing HOOKS line)
_hooks_line="HOOKS=(${GTLTSC_MKINITCPIO_HOOKS})"

if grep -q "^HOOKS=" "${_ROOT}/etc/mkinitcpio.conf"; then
    sed -i "s|^HOOKS=.*|${_hooks_line}|" "${_ROOT}/etc/mkinitcpio.conf" \
        || die "Failed to update mkinitcpio HOOKS"
else
    printf '%s\n' "${_hooks_line}" >> "${_ROOT}/etc/mkinitcpio.conf"
fi

# Verify the hooks line was written correctly
if ! grep -qF "${_hooks_line}" "${_ROOT}/etc/mkinitcpio.conf"; then
    die "mkinitcpio.conf does not contain expected HOOKS line"
fi

# Rebuild initramfs — ALWAYS after hook changes
log "Rebuilding initramfs (this takes a moment on HDD)..."
safe_chroot "mkinitcpio -P" || die "mkinitcpio failed"

# Verify initramfs was rebuilt (check timestamp is recent)
verify_file "${_ROOT}/boot/initramfs-linux-lts.img" "Rebuilt initramfs"

# Verify plymouth hook is inside the initramfs
log "Verifying plymouth hook inside initramfs..."
if ! safe_chroot "lsinitcpio /boot/initramfs-linux-lts.img" 2>/dev/null | grep -q "plymouth"; then
    warn "Plymouth hook not detected in initramfs — boot splash may not work"
fi

log "mkinitcpio configured and rebuilt ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  GRUB BOOTLOADER
# ═══════════════════════════════════════════════════════════════════════════════

log "Installing GRUB (UEFI removable mode)..."

safe_chroot "grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot \
    --bootloader-id=GRUB \
    --removable" \
    || die "grub-install failed"

# Verify EFI binary exists at the removable path
verify_file "${_ROOT}/boot/EFI/BOOT/BOOTX64.EFI" "GRUB EFI payload (removable)"

# Configure GRUB defaults
log "Configuring GRUB..."

_grub_default="${_ROOT}/etc/default/grub"

# GRUB_TIMEOUT
if grep -q "^GRUB_TIMEOUT=" "${_grub_default}"; then
    sed -i "s|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=${GTLTSC_GRUB_TIMEOUT}|" "${_grub_default}"
else
    printf 'GRUB_TIMEOUT=%s\n' "${GTLTSC_GRUB_TIMEOUT}" >> "${_grub_default}"
fi

# GRUB_CMDLINE_LINUX_DEFAULT — quiet boot with plymouth splash
_grub_cmdline="quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0"
if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "${_grub_default}"; then
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${_grub_cmdline}\"|" "${_grub_default}"
else
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="%s"\n' "${_grub_cmdline}" >> "${_grub_default}"
fi

# Generate GRUB config
safe_chroot "grub-mkconfig -o /boot/grub/grub.cfg" \
    || die "grub-mkconfig failed"

verify_file "${_ROOT}/boot/grub/grub.cfg" "GRUB config"

# Verify grub.cfg contains at least one menuentry
if ! grep -q "menuentry" "${_ROOT}/boot/grub/grub.cfg"; then
    die "grub.cfg contains no menu entries — system will not boot"
fi

# Verify grub.cfg references the correct kernel
if ! grep -q "vmlinuz-linux-lts" "${_ROOT}/boot/grub/grub.cfg"; then
    die "grub.cfg does not reference linux-lts kernel"
fi

log "GRUB installed and configured ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  PLYMOUTH THEME
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring Plymouth spinner theme..."
safe_chroot "plymouth-set-default-theme -R spinner" 2>/dev/null \
    || warn "Plymouth theme set failed (non-fatal — default will be used)"

log "Plymouth configured ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  PERFORMANCE TUNING
# ═══════════════════════════════════════════════════════════════════════════════

log "Applying performance tuning..."

# ── ZRAM Configuration ───────────────────────────────────────────────────────
# Using systemd-zram-setup@.service via zram-generator
ensure_dir "${_ROOT}/etc/systemd/zram-generator.conf.d"

safe_write_heredoc "${_ROOT}/etc/systemd/zram-generator.conf" <<EOF
# God-Tier LTSC — ZRAM Configuration
# 100% of RAM as ZRAM swap with zstd compression
[zram0]
zram-size = ram
compression-algorithm = ${GTLTSC_ZRAM_ALGORITHM}
swap-priority = 100
fs-type = swap
EOF

# ── sysctl — VM tuning ──────────────────────────────────────────────────────
safe_write_heredoc "${_ROOT}/etc/sysctl.d/99-ltsc-performance.conf" <<EOF
# God-Tier LTSC — Performance Tuning
# Aggressively use ZRAM swap (100% RAM, zstd)
vm.swappiness = ${GTLTSC_SWAPPINESS}
# Reduce dirty page writeback thresholds for HDD
vm.dirty_background_ratio = ${GTLTSC_DIRTY_BG_RATIO}
vm.dirty_ratio = ${GTLTSC_DIRTY_RATIO}
# Moderate VFS cache pressure
vm.vfs_cache_pressure = ${GTLTSC_VFS_CACHE_PRESSURE}
EOF

# ── udev — BFQ scheduler + HDD read_ahead ───────────────────────────────────
safe_write_heredoc "${_ROOT}/etc/udev/rules.d/60-io-scheduler.rules" <<EOF
# God-Tier LTSC — I/O Scheduler
# Set BFQ for all rotational (HDD) devices
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
# Set read_ahead_kb for rotational devices
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/read_ahead_kb}="${GTLTSC_HDD_READ_AHEAD_KB}"
EOF

# ── EarlyOOM ─────────────────────────────────────────────────────────────────
# Default config is usually fine for 4GB RAM. Just ensure it starts.

# ── Journald — limit disk usage ─────────────────────────────────────────────
ensure_dir "${_ROOT}/etc/systemd/journald.conf.d"
safe_write_heredoc "${_ROOT}/etc/systemd/journald.conf.d/50-ltsc.conf" <<EOF
[Journal]
SystemMaxUse=${GTLTSC_JOURNAL_MAX_USE}
EOF

log "Performance tuning applied ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  NETWORK MANAGER
# ═══════════════════════════════════════════════════════════════════════════════

log "Enabling NetworkManager..."
safe_chroot "systemctl enable NetworkManager.service" \
    || die "Failed to enable NetworkManager"
log "NetworkManager enabled ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  SYSTEM SERVICES
# ═══════════════════════════════════════════════════════════════════════════════

log "Enabling system services..."

for svc in "${GTLTSC_SERVICES_SYSTEM[@]}"; do
    # Verify the service unit exists before enabling
    if safe_chroot "systemctl list-unit-files ${svc}.service" 2>/dev/null | grep -q "${svc}"; then
        safe_chroot "systemctl enable ${svc}.service" \
            || warn "Failed to enable ${svc} (non-fatal)"
        log "Enabled: ${svc}"
    else
        warn "Service unit not found, skipping: ${svc}"
    fi
done

# ── PipeWire global user services ────────────────────────────────────────────
log "Enabling PipeWire user services (global)..."
for svc in "${GTLTSC_SERVICES_USER_GLOBAL[@]}"; do
    # --global enables for all users at login
    safe_chroot "systemctl --global enable ${svc}.service" 2>/dev/null \
        || safe_chroot "systemctl --global enable ${svc}" 2>/dev/null \
        || warn "Failed to globally enable user service: ${svc}"
    log "Globally enabled user service: ${svc}"
done

log "System services configured ✓"
log "Core configuration stage complete ✓"
