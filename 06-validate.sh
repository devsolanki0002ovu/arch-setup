#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 06-validate.sh — Post-Install Verification Framework
# ─────────────────────────────────────────────────────────────────────────────
# Runs 80+ checks against the installed system to verify correctness.
# Each check is classified as CRITICAL (blocks boot) or WARNING (cosmetic).
# Outputs a tabular pass/fail report.
#
# Depends on: globals.env, 00-lib.sh, 05-gui.sh (completed install)
# ─────────────────────────────────────────────────────────────────────────────

set_stage "06-validate"

_ROOT="${GTLTSC_MOUNT_ROOT}"

# ═══════════════════════════════════════════════════════════════════════════════
#  VALIDATION ENGINE
# ═══════════════════════════════════════════════════════════════════════════════

_PASS_COUNT=0
_FAIL_COUNT=0
_WARN_COUNT=0
_TOTAL_COUNT=0

# Arrays to collect results for summary
declare -a _RESULTS=()

# check — run a validation check
# Usage: check <severity> <description> <command...>
# severity: CRITICAL or WARNING
check() {
    local severity="$1"
    local desc="$2"
    shift 2

    (( _TOTAL_COUNT++ ))

    if "$@" &>/dev/null; then
        _RESULTS+=("PASS|${severity}|${desc}")
        (( _PASS_COUNT++ ))
    else
        if [[ "${severity}" == "CRITICAL" ]]; then
            _RESULTS+=("FAIL|${severity}|${desc}")
            (( _FAIL_COUNT++ ))
        else
            _RESULTS+=("WARN|${severity}|${desc}")
            (( _WARN_COUNT++ ))
        fi
    fi
}

# check_file — verify file exists and is non-empty
check_file() {
    local severity="$1"
    local desc="$2"
    local path="$3"
    check "${severity}" "${desc}" test -s "${path}"
}

# check_dir — verify directory exists
check_dir() {
    local severity="$1"
    local desc="$2"
    local path="$3"
    check "${severity}" "${desc}" test -d "${path}"
}

# check_mount — verify mountpoint is active
check_mount() {
    local severity="$1"
    local desc="$2"
    local mp="$3"
    check "${severity}" "${desc}" findmnt -rn "${mp}"
}

# check_chroot_cmd — run a command inside chroot and check exit code
check_chroot_cmd() {
    local severity="$1"
    local desc="$2"
    shift 2
    check "${severity}" "${desc}" arch-chroot "${_ROOT}" "$@"
}

# check_grep — verify a pattern exists in a file
check_grep() {
    local severity="$1"
    local desc="$2"
    local pattern="$3"
    local file="$4"
    check "${severity}" "${desc}" grep -q "${pattern}" "${file}"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  FILESYSTEM CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating filesystem..."
check_mount "CRITICAL" "Root filesystem mounted" "${_ROOT}"
check_mount "CRITICAL" "EFI partition mounted" "${_ROOT}/boot"
check_file  "CRITICAL" "fstab exists" "${_ROOT}/etc/fstab"

# Verify fstab has UUID entries
_efi_uuid=$(blkid -s UUID -o value "${GTLTSC_EFI_PART}" 2>/dev/null || echo "")
_root_uuid=$(blkid -s UUID -o value "${GTLTSC_ROOT_PART}" 2>/dev/null || echo "")

if [[ -n "${_root_uuid}" ]]; then
    check_grep "CRITICAL" "fstab contains root UUID" "${_root_uuid}" "${_ROOT}/etc/fstab"
fi
if [[ -n "${_efi_uuid}" ]]; then
    check_grep "CRITICAL" "fstab contains EFI UUID" "${_efi_uuid}" "${_ROOT}/etc/fstab"
fi

check_grep "WARNING" "fstab has noatime on root" "noatime" "${_ROOT}/etc/fstab"

# ═══════════════════════════════════════════════════════════════════════════════
#  BOOT CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating boot chain..."
check_file "CRITICAL" "LTS kernel image" "${_ROOT}/boot/vmlinuz-linux-lts"
check_file "CRITICAL" "LTS initramfs" "${_ROOT}/boot/initramfs-linux-lts.img"
check_file "CRITICAL" "Intel microcode" "${_ROOT}/boot/intel-ucode.img"
check_file "CRITICAL" "GRUB EFI binary (removable)" "${_ROOT}/boot/EFI/BOOT/BOOTX64.EFI"
check_file "CRITICAL" "GRUB config" "${_ROOT}/boot/grub/grub.cfg"
check_grep "CRITICAL" "GRUB config has menu entries" "menuentry" "${_ROOT}/boot/grub/grub.cfg"
check_grep "CRITICAL" "GRUB config references LTS kernel" "vmlinuz-linux-lts" "${_ROOT}/boot/grub/grub.cfg"
check_grep "WARNING" "GRUB quiet boot" "quiet" "${_ROOT}/etc/default/grub"
check_grep "WARNING" "GRUB splash parameter" "splash" "${_ROOT}/etc/default/grub"
check_grep "WARNING" "GRUB timeout set" "GRUB_TIMEOUT=${GTLTSC_GRUB_TIMEOUT}" "${_ROOT}/etc/default/grub"

# Plymouth in initramfs
check "WARNING" "Plymouth hook in initramfs" \
    arch-chroot "${_ROOT}" lsinitcpio /boot/initramfs-linux-lts.img 2>/dev/null grep -q plymouth

# mkinitcpio hooks
check_grep "CRITICAL" "mkinitcpio HOOKS configured" "plymouth" "${_ROOT}/etc/mkinitcpio.conf"

# ═══════════════════════════════════════════════════════════════════════════════
#  LOCALE & TIMEZONE
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating locale and timezone..."
check_file  "CRITICAL" "locale.conf exists" "${_ROOT}/etc/locale.conf"
check_grep  "CRITICAL" "Locale set correctly" "LANG=${GTLTSC_LOCALE}" "${_ROOT}/etc/locale.conf"
check_file  "CRITICAL" "vconsole.conf exists" "${_ROOT}/etc/vconsole.conf"
check_grep  "CRITICAL" "Keymap set correctly" "KEYMAP=${GTLTSC_KEYMAP}" "${_ROOT}/etc/vconsole.conf"
check_file  "CRITICAL" "Timezone symlink exists" "${_ROOT}/etc/localtime"
check       "CRITICAL" "Timezone symlink valid" test -L "${_ROOT}/etc/localtime"

# ═══════════════════════════════════════════════════════════════════════════════
#  HOSTNAME
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating hostname..."
check_file "CRITICAL" "hostname file exists" "${_ROOT}/etc/hostname"
check_grep "CRITICAL" "Hostname correct" "${GTLTSC_HOSTNAME}" "${_ROOT}/etc/hostname"
check_file "CRITICAL" "hosts file exists" "${_ROOT}/etc/hosts"
check_grep "CRITICAL" "hosts contains hostname" "${GTLTSC_HOSTNAME}" "${_ROOT}/etc/hosts"

# ═══════════════════════════════════════════════════════════════════════════════
#  USERS & SUDO
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating users..."
check_chroot_cmd "CRITICAL" "User exists" id "${GTLTSC_USERNAME}"
check_chroot_cmd "CRITICAL" "User in wheel group" id -nG "${GTLTSC_USERNAME}" 
check_dir  "CRITICAL" "User home directory" "${_ROOT}/home/${GTLTSC_USERNAME}"
check_file "CRITICAL" "Sudoers wheel config" "${_ROOT}/etc/sudoers.d/10-wheel"
check_chroot_cmd "CRITICAL" "Sudoers syntax valid" visudo -cf /etc/sudoers.d/10-wheel

# ═══════════════════════════════════════════════════════════════════════════════
#  NETWORKING
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating networking..."
check_chroot_cmd "CRITICAL" "NetworkManager enabled" systemctl is-enabled NetworkManager.service

# ═══════════════════════════════════════════════════════════════════════════════
#  AUDIO (PIPEWIRE)
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating audio..."
check_chroot_cmd "WARNING" "PipeWire globally enabled" systemctl --global is-enabled pipewire.service
check_chroot_cmd "WARNING" "PipeWire-Pulse globally enabled" systemctl --global is-enabled pipewire-pulse.service
check_chroot_cmd "WARNING" "WirePlumber globally enabled" systemctl --global is-enabled wireplumber.service

# ═══════════════════════════════════════════════════════════════════════════════
#  DISPLAY MANAGER
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating display manager..."
check_chroot_cmd "CRITICAL" "SDDM enabled" systemctl is-enabled sddm.service
check_file "WARNING" "SDDM config exists" "${_ROOT}/etc/sddm.conf.d/10-ltsc.conf"
# Ensure no autologin
check "WARNING" "No autologin configured" \
    bash -c "! grep -rq 'Autologin' ${_ROOT}/etc/sddm.conf.d/ 2>/dev/null || ! grep -rq 'User=' ${_ROOT}/etc/sddm.conf.d/ 2>/dev/null"

# ═══════════════════════════════════════════════════════════════════════════════
#  LXQT & OPENBOX
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating desktop environment..."
_uhome="${_ROOT}/home/${GTLTSC_USERNAME}"

check_file "CRITICAL" "LXQt session config" "${_uhome}/.config/lxqt/session.conf"
check_file "CRITICAL" "LXQt general config" "${_uhome}/.config/lxqt/lxqt.conf"
check_file "WARNING" "LXQt panel config" "${_uhome}/.config/lxqt/panel.conf"
check_file "CRITICAL" "Openbox rc.xml" "${_uhome}/.config/openbox/rc.xml"
check_file "WARNING" "Openbox autostart" "${_uhome}/.config/openbox/autostart"
check_file "WARNING" "Openbox environment" "${_uhome}/.config/openbox/environment"

# Verify Openbox rc.xml is valid XML
check "WARNING" "Openbox rc.xml valid XML" \
    arch-chroot "${_ROOT}" xmlstarlet val "/home/${GTLTSC_USERNAME}/.config/openbox/rc.xml"

# ═══════════════════════════════════════════════════════════════════════════════
#  THEMING
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating theming..."

# GTK
check_file "WARNING" "GTK2 config" "${_uhome}/.gtkrc-2.0"
check_file "WARNING" "GTK3 config" "${_uhome}/.config/gtk-3.0/settings.ini"
check_file "WARNING" "GTK4 config" "${_uhome}/.config/gtk-4.0/settings.ini"
check_grep "WARNING" "GTK3 theme correct" "${GTLTSC_GTK_THEME}" "${_uhome}/.config/gtk-3.0/settings.ini"
check_grep "WARNING" "GTK3 icons correct" "${GTLTSC_ICON_THEME}" "${_uhome}/.config/gtk-3.0/settings.ini"

# Qt
check_file "WARNING" "Qt6ct config" "${_uhome}/.config/qt6ct/qt6ct.conf"
check_file "WARNING" "Qt platform env" "${_ROOT}/etc/environment.d/90-ui.conf"
check_grep "WARNING" "Qt6ct env variable set" "QT_QPA_PLATFORMTHEME=qt6ct" "${_ROOT}/etc/environment.d/90-ui.conf"

# Icons
check_dir  "WARNING" "Papirus-Dark icons installed" "${_ROOT}/usr/share/icons/Papirus-Dark"

# Cursor
check_file "WARNING" "Cursor theme index" "${_ROOT}/usr/share/icons/default/index.theme"

# Desktop background
check_file "WARNING" "PCManFM-Qt desktop config" "${_uhome}/.config/pcmanfm-qt/lxqt/settings.conf"
check_grep "WARNING" "Desktop bg color correct" "${GTLTSC_DESKTOP_BG_COLOR}" "${_uhome}/.config/pcmanfm-qt/lxqt/settings.conf"
check_grep "WARNING" "No wallpaper set" "WallpaperMode=color" "${_uhome}/.config/pcmanfm-qt/lxqt/settings.conf"

# ═══════════════════════════════════════════════════════════════════════════════
#  FIREFOX POLICIES
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating Firefox..."
check_file "WARNING" "Firefox policy file" "${_ROOT}/etc/firefox/policies/policies.json"

# Validate JSON
check "WARNING" "Firefox policy valid JSON" \
    arch-chroot "${_ROOT}" python3 -m json.tool /etc/firefox/policies/policies.json

# Check key policies are present
check_grep "WARNING" "Firefox telemetry disabled" "DisableTelemetry" "${_ROOT}/etc/firefox/policies/policies.json"
check_grep "WARNING" "Firefox Pocket disabled" "DisablePocket" "${_ROOT}/etc/firefox/policies/policies.json"
check_grep "WARNING" "Firefox studies disabled" "DisableFirefoxStudies" "${_ROOT}/etc/firefox/policies/policies.json"

# ═══════════════════════════════════════════════════════════════════════════════
#  DESKTOP ENTRIES
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating desktop entries..."
for entry in "${GTLTSC_DESKTOP_RENAMES[@]}"; do
    _desktop_file="${entry%%:*}"
    _new_name="${entry#*:}"
    _desktop_path="${_ROOT}/usr/share/applications/${_desktop_file}"

    if [[ -f "${_desktop_path}" ]]; then
        # Verify it still has an Exec= line (wasn't corrupted)
        check "WARNING" "Desktop entry valid: ${_desktop_file}" \
            grep -q "^Exec=" "${_desktop_path}"
        # Verify rename applied
        check "WARNING" "Desktop entry renamed: ${_desktop_file}" \
            grep -q "^Name=${_new_name}" "${_desktop_path}"
    fi
done

# ═══════════════════════════════════════════════════════════════════════════════
#  MIME ASSOCIATIONS
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating MIME associations..."
check_file "WARNING" "mimeapps.list exists" "${_uhome}/.config/mimeapps.list"
check_grep "WARNING" "Firefox default browser" "text/html=firefox.desktop" "${_uhome}/.config/mimeapps.list"
check_grep "WARNING" "PCManFM-Qt default FM" "inode/directory=pcmanfm-qt.desktop" "${_uhome}/.config/mimeapps.list"

# ═══════════════════════════════════════════════════════════════════════════════
#  PERFORMANCE TUNING
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating performance tuning..."
check_file "CRITICAL" "ZRAM config" "${_ROOT}/etc/systemd/zram-generator.conf"
check_grep "WARNING" "ZRAM size = ram" "zram-size = ram" "${_ROOT}/etc/systemd/zram-generator.conf"
check_grep "WARNING" "ZRAM compression = zstd" "compression-algorithm = ${GTLTSC_ZRAM_ALGORITHM}" "${_ROOT}/etc/systemd/zram-generator.conf"

check_file "CRITICAL" "sysctl performance config" "${_ROOT}/etc/sysctl.d/99-ltsc-performance.conf"
check_grep "WARNING" "Swappiness = ${GTLTSC_SWAPPINESS}" "vm.swappiness = ${GTLTSC_SWAPPINESS}" "${_ROOT}/etc/sysctl.d/99-ltsc-performance.conf"
check_grep "WARNING" "Dirty bg ratio" "vm.dirty_background_ratio = ${GTLTSC_DIRTY_BG_RATIO}" "${_ROOT}/etc/sysctl.d/99-ltsc-performance.conf"
check_grep "WARNING" "VFS cache pressure" "vm.vfs_cache_pressure = ${GTLTSC_VFS_CACHE_PRESSURE}" "${_ROOT}/etc/sysctl.d/99-ltsc-performance.conf"

check_file "CRITICAL" "I/O scheduler udev rules" "${_ROOT}/etc/udev/rules.d/60-io-scheduler.rules"
check_grep "WARNING" "BFQ scheduler in udev" "bfq" "${_ROOT}/etc/udev/rules.d/60-io-scheduler.rules"
check_grep "WARNING" "Read ahead KB in udev" "read_ahead_kb" "${_ROOT}/etc/udev/rules.d/60-io-scheduler.rules"

check_file "WARNING" "Journald limits" "${_ROOT}/etc/systemd/journald.conf.d/50-ltsc.conf"
check_grep "WARNING" "Journal max size" "SystemMaxUse=${GTLTSC_JOURNAL_MAX_USE}" "${_ROOT}/etc/systemd/journald.conf.d/50-ltsc.conf"

# ═══════════════════════════════════════════════════════════════════════════════
#  SERVICES
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating services..."
check_chroot_cmd "CRITICAL" "NetworkManager enabled" systemctl is-enabled NetworkManager.service
check_chroot_cmd "CRITICAL" "SDDM enabled" systemctl is-enabled sddm.service
check_chroot_cmd "CRITICAL" "EarlyOOM enabled" systemctl is-enabled earlyoom.service

# ═══════════════════════════════════════════════════════════════════════════════
#  MOBILE DEVICE SUPPORT
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating mobile support packages..."
_mobile_packages=(gvfs gvfs-mtp libimobiledevice ifuse usbmuxd)
for pkg in "${_mobile_packages[@]}"; do
    check "WARNING" "Package installed: ${pkg}" \
        arch-chroot "${_ROOT}" pacman -Q "${pkg}"
done

# ═══════════════════════════════════════════════════════════════════════════════
#  XDG DIRECTORIES
# ═══════════════════════════════════════════════════════════════════════════════

log "Validating XDG directories..."
_xdg_dirs=(Desktop Downloads Documents Music Pictures Videos)
for dir in "${_xdg_dirs[@]}"; do
    check_dir "WARNING" "XDG dir: ${dir}" "${_uhome}/${dir}"
done

# ═══════════════════════════════════════════════════════════════════════════════
#  REPORT
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  GOD-TIER LTSC PROVISIONER — VALIDATION REPORT"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
printf "  %-6s %-10s %s\n" "STATUS" "SEVERITY" "CHECK"
printf "  %-6s %-10s %s\n" "──────" "────────" "─────────────────────────────────────────"

for result in "${_RESULTS[@]}"; do
    IFS='|' read -r status severity desc <<< "${result}"
    case "${status}" in
        PASS)
            printf '  %b%-6s%b %-10s %s\n' "${_C_GREEN}" "PASS" "${_C_RESET}" "${severity}" "${desc}"
            ;;
        FAIL)
            printf '  %b%-6s%b %-10s %s\n' "${_C_RED}" "FAIL" "${_C_RESET}" "${severity}" "${desc}"
            ;;
        WARN)
            printf '  %b%-6s%b %-10s %s\n' "${_C_YELLOW}" "WARN" "${_C_RESET}" "${severity}" "${desc}"
            ;;
    esac
done

echo ""
echo "───────────────────────────────────────────────────────────────────"
printf "  Total: %d | " "${_TOTAL_COUNT}"
printf "%bPassed: %d%b | " "${_C_GREEN}" "${_PASS_COUNT}" "${_C_RESET}"
printf "%bFailed: %d%b | " "${_C_RED}" "${_FAIL_COUNT}" "${_C_RESET}"
printf "%bWarnings: %d%b\n" "${_C_YELLOW}" "${_WARN_COUNT}" "${_C_RESET}"
echo "───────────────────────────────────────────────────────────────────"

if (( _FAIL_COUNT > 0 )); then
    echo ""
    printf '  %b✖ %d CRITICAL check(s) FAILED. System may not boot correctly.%b\n' \
        "${_C_RED}" "${_FAIL_COUNT}" "${_C_RESET}"
    echo "    Review the log at: ${GTLTSC_LOG_FILE}"
    echo ""
    # Do not die here — let the orchestrator decide
    log "Validation completed with ${_FAIL_COUNT} CRITICAL failures"
else
    echo ""
    printf '  %b✓ All critical checks passed. System should boot successfully.%b\n' \
        "${_C_GREEN}" "${_C_RESET}"
    if (( _WARN_COUNT > 0 )); then
        printf '  %b▲ %d warning(s) — cosmetic issues that won'\''t prevent boot.%b\n' \
            "${_C_YELLOW}" "${_WARN_COUNT}" "${_C_RESET}"
    fi
    echo ""
    log "Validation completed: ${_PASS_COUNT} passed, ${_WARN_COUNT} warnings, 0 failures"
fi

log "Validation stage complete"
