#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 00-lib.sh — God-Tier LTSC Provisioner Shared Library
# ─────────────────────────────────────────────────────────────────────────────
# Sourced by every module. Provides logging, validation, rollback, retry,
# atomic write, and chroot helpers.
#
# IMPORTANT: This file must be sourced, never executed directly.
# ─────────────────────────────────────────────────────────────────────────────

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: 00-lib.sh must be sourced, not executed." >&2
    exit 1
fi

# Guard against double-sourcing
if [[ "${_GTLTSC_LIB_LOADED:-}" == "1" ]]; then
    return 0
fi
_GTLTSC_LIB_LOADED=1

# ── ANSI Colors ──────────────────────────────────────────────────────────────
readonly _C_RESET='\033[0m'
readonly _C_RED='\033[1;31m'
readonly _C_YELLOW='\033[1;33m'
readonly _C_GREEN='\033[1;32m'
readonly _C_CYAN='\033[1;36m'
readonly _C_DIM='\033[0;37m'

# ═══════════════════════════════════════════════════════════════════════════════
#  LOGGING
# ═══════════════════════════════════════════════════════════════════════════════

# Ensure log directory and file exist
_init_logging() {
    install -d -m 0755 "${GTLTSC_LOG_DIR}"
    touch "${GTLTSC_LOG_FILE}"
}

# log — informational message
# Usage: log "message"
log() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local msg="[${timestamp}] [INFO]  [${GTLTSC_CURRENT_STAGE}] $*"
    printf '%b\n' "${_C_GREEN}●${_C_RESET} ${msg}"
    printf '%s\n' "${msg}" >> "${GTLTSC_LOG_FILE}" 2>/dev/null || true
}

# warn — warning message (non-fatal)
# Usage: warn "message"
warn() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local msg="[${timestamp}] [WARN]  [${GTLTSC_CURRENT_STAGE}] $*"
    printf '%b\n' "${_C_YELLOW}▲${_C_RESET} ${msg}" >&2
    printf '%s\n' "${msg}" >> "${GTLTSC_LOG_FILE}" 2>/dev/null || true
}

# die — fatal error: log, trigger rollback, exit
# Usage: die "message"
die() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local msg="[${timestamp}] [FATAL] [${GTLTSC_CURRENT_STAGE}] $*"
    printf '%b\n' "${_C_RED}✖ FATAL: ${msg}${_C_RESET}" >&2
    printf '%s\n' "${msg}" >> "${GTLTSC_LOG_FILE}" 2>/dev/null || true
    # Rollback is called from the ERR/EXIT trap in install.sh, not here,
    # to avoid double-rollback. We simply exit.
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ROLLBACK & CLEANUP
# ═══════════════════════════════════════════════════════════════════════════════

# rollback — clean up mounts, swap, and temporary state
# Called from the ERR trap in install.sh. Safe to call multiple times.
rollback() {
    local exit_code="${1:-$?}"

    # Prevent recursive rollback
    if [[ "${_GTLTSC_ROLLBACK_RUNNING:-0}" == "1" ]]; then
        return 0
    fi
    _GTLTSC_ROLLBACK_RUNNING=1

    printf '\n%b\n' "${_C_RED}═══ ROLLBACK INITIATED ═══${_C_RESET}" >&2
    printf '%b\n' "${_C_RED}  Stage:     ${GTLTSC_CURRENT_STAGE}${_C_RESET}" >&2
    printf '%b\n' "${_C_RED}  Exit Code: ${exit_code}${_C_RESET}" >&2

    # Disable ZRAM if active
    if [[ -b /dev/zram0 ]]; then
        swapoff /dev/zram0 2>/dev/null || true
        echo 1 > /sys/block/zram0/reset 2>/dev/null || true
    fi

    # Unmount in reverse order — deepest first
    local mount_root="${GTLTSC_MOUNT_ROOT:-/mnt}"
    local -a mount_points=()

    # Collect active mounts under our root, sorted deepest-first
    while IFS= read -r mp; do
        mount_points+=("${mp}")
    done < <(findmnt -Rrn -o TARGET "${mount_root}" 2>/dev/null | sort -r)

    for mp in "${mount_points[@]}"; do
        if findmnt -rn "${mp}" &>/dev/null; then
            printf '%b\n' "${_C_DIM}  Unmounting: ${mp}${_C_RESET}" >&2
            umount -R "${mp}" 2>/dev/null || umount -l "${mp}" 2>/dev/null || true
        fi
    done

    # Save log to a persistent location
    if [[ -f "${GTLTSC_LOG_FILE}" ]]; then
        local rescue_log="/root/god-tier-ltsc-failure-$(date '+%Y%m%d-%H%M%S').log"
        cp "${GTLTSC_LOG_FILE}" "${rescue_log}" 2>/dev/null || true
        printf '%b\n' "${_C_YELLOW}  Log saved: ${rescue_log}${_C_RESET}" >&2
    fi

    printf '%b\n' "${_C_RED}═══ ROLLBACK COMPLETE ═══${_C_RESET}" >&2
    _GTLTSC_ROLLBACK_RUNNING=0
}

# ═══════════════════════════════════════════════════════════════════════════════
#  RETRY LOGIC
# ═══════════════════════════════════════════════════════════════════════════════

# retry — run a command up to N times with exponential backoff
# Usage: retry <max_attempts> <delay_seconds> <command> [args...]
retry() {
    local max_attempts="$1"
    local base_delay="$2"
    shift 2

    local attempt=1
    local delay="${base_delay}"

    while (( attempt <= max_attempts )); do
        log "Attempt ${attempt}/${max_attempts}: $*"
        if "$@"; then
            return 0
        fi
        warn "Attempt ${attempt}/${max_attempts} failed for: $*"
        if (( attempt < max_attempts )); then
            log "Waiting ${delay}s before retry..."
            sleep "${delay}"
            delay=$(( delay * 2 ))
        fi
        (( attempt++ ))
    done

    die "All ${max_attempts} attempts failed for: $*"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  DIRECTORY & FILE HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

# ensure_dir — create directory (and parents) with specified permissions
# Usage: ensure_dir <path> [mode]
ensure_dir() {
    local path="$1"
    local mode="${2:-0755}"

    if [[ ! -d "${path}" ]]; then
        install -d -m "${mode}" "${path}"
        log "Created directory: ${path} (mode ${mode})"
    fi
}

# safe_write — write content to a file atomically
# Creates parent directories. Writes to a temp file first, then mv.
# Usage: safe_write <destination> <content> [mode]
safe_write() {
    local dest="$1"
    local content="$2"
    local mode="${3:-0644}"

    # Create parent directory
    ensure_dir "$(dirname "${dest}")"

    # Write to temp file in same directory (same filesystem for atomic mv)
    local tmpfile
    tmpfile="$(dirname "${dest}")/.tmp.$(basename "${dest}").$$"

    printf '%s\n' "${content}" > "${tmpfile}"
    chmod "${mode}" "${tmpfile}"
    mv -f "${tmpfile}" "${dest}"
    log "Wrote: ${dest} (mode ${mode})"
}

# safe_write_heredoc — write stdin (heredoc) to a file atomically
# Usage: safe_write_heredoc <destination> [mode] <<'EOF'
#   content here
# EOF
safe_write_heredoc() {
    local dest="$1"
    local mode="${2:-0644}"

    ensure_dir "$(dirname "${dest}")"

    local tmpfile
    tmpfile="$(dirname "${dest}")/.tmp.$(basename "${dest}").$$"

    cat > "${tmpfile}"
    chmod "${mode}" "${tmpfile}"
    mv -f "${tmpfile}" "${dest}"
    log "Wrote: ${dest} (mode ${mode})"
}

# idempotent_line — add a line to a file only if not already present
# Usage: idempotent_line <file> <line>
idempotent_line() {
    local file="$1"
    local line="$2"

    ensure_dir "$(dirname "${file}")"
    touch "${file}"

    if ! grep -qxF "${line}" "${file}"; then
        printf '%s\n' "${line}" >> "${file}"
        log "Added line to ${file}: ${line}"
    else
        log "Line already present in ${file}: ${line}"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  VERIFICATION HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

# verify_file — assert file exists and is non-empty
# Usage: verify_file <path> [description]
verify_file() {
    local path="$1"
    local desc="${2:-${path}}"
    if [[ ! -f "${path}" ]]; then
        die "Verification failed: file does not exist: ${desc} (${path})"
    fi
    if [[ ! -s "${path}" ]]; then
        die "Verification failed: file is empty: ${desc} (${path})"
    fi
    log "Verified file: ${desc}"
}

# verify_directory — assert directory exists
# Usage: verify_directory <path> [description]
verify_directory() {
    local path="$1"
    local desc="${2:-${path}}"
    if [[ ! -d "${path}" ]]; then
        die "Verification failed: directory does not exist: ${desc} (${path})"
    fi
    log "Verified directory: ${desc}"
}

# verify_mount — assert mountpoint is active
# Usage: verify_mount <mountpoint> [description]
verify_mount() {
    local mountpoint="$1"
    local desc="${2:-${mountpoint}}"
    if ! findmnt -rn "${mountpoint}" &>/dev/null; then
        die "Verification failed: not mounted: ${desc} (${mountpoint})"
    fi
    log "Verified mount: ${desc}"
}

# verify_package — assert package is installed (inside chroot or host)
# Usage: verify_package <package_name> [root_path]
verify_package() {
    local pkg="$1"
    local root="${2:-}"

    if [[ -n "${root}" ]]; then
        if ! arch-chroot "${root}" pacman -Q "${pkg}" &>/dev/null; then
            die "Verification failed: package not installed in chroot: ${pkg}"
        fi
    else
        if ! pacman -Q "${pkg}" &>/dev/null; then
            die "Verification failed: package not installed: ${pkg}"
        fi
    fi
    log "Verified package: ${pkg}"
}

# verify_service — assert systemd service exists and is enabled
# Usage: verify_service <service_name> [root_path]
verify_service() {
    local svc="$1"
    local root="${2:-}"

    if [[ -n "${root}" ]]; then
        # Check inside chroot
        if ! arch-chroot "${root}" systemctl is-enabled "${svc}" &>/dev/null; then
            die "Verification failed: service not enabled in chroot: ${svc}"
        fi
    else
        if ! systemctl is-enabled "${svc}" &>/dev/null; then
            die "Verification failed: service not enabled: ${svc}"
        fi
    fi
    log "Verified service enabled: ${svc}"
}

# verify_command — assert command is available
# Usage: verify_command <command_name>
verify_command() {
    local cmd="$1"
    if ! command -v "${cmd}" &>/dev/null; then
        die "Verification failed: command not found: ${cmd}"
    fi
    log "Verified command: ${cmd}"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  PRECONDITION CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

# require_root — assert running as root
require_root() {
    if (( EUID != 0 )); then
        die "This script must be run as root (EUID=0). Current EUID: ${EUID}"
    fi
    log "Running as root (EUID=0)"
}

# require_uefi — assert booted in UEFI mode
require_uefi() {
    if [[ ! -d /sys/firmware/efi/efivars ]]; then
        die "System is not booted in UEFI mode. /sys/firmware/efi/efivars not found."
    fi
    log "UEFI boot mode confirmed"
}

# require_network — assert network connectivity
require_network() {
    log "Checking network connectivity..."
    if ! ping -c 1 -W 5 archlinux.org &>/dev/null; then
        if ! ping -c 1 -W 5 1.1.1.1 &>/dev/null; then
            die "No network connectivity. Cannot reach archlinux.org or 1.1.1.1"
        fi
        warn "DNS may be impaired — reached 1.1.1.1 but not archlinux.org"
    fi
    log "Network connectivity confirmed"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  INPUT VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

# validate_username — validate a Linux username
# Rules: 1-32 chars, starts with [a-z_], contains only [a-z0-9_-]
# Usage: validate_username <username>
validate_username() {
    local name="$1"
    if [[ -z "${name}" ]]; then
        die "Username cannot be empty"
    fi
    if (( ${#name} > 32 )); then
        die "Username too long (max 32 chars): ${name}"
    fi
    if [[ ! "${name}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        die "Invalid username: '${name}'. Must start with [a-z_], contain only [a-z0-9_-]"
    fi
    log "Username validated: ${name}"
}

# validate_hostname — validate an RFC 1123 hostname
# Rules: 1-63 chars, [a-zA-Z0-9-], no leading/trailing hyphen
# Usage: validate_hostname <hostname>
validate_hostname() {
    local name="$1"
    if [[ -z "${name}" ]]; then
        die "Hostname cannot be empty"
    fi
    if (( ${#name} > 63 )); then
        die "Hostname too long (max 63 chars): ${name}"
    fi
    if [[ ! "${name}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
        die "Invalid hostname: '${name}'. Must be RFC 1123 compliant (alphanumeric + hyphens, no leading/trailing hyphen)"
    fi
    log "Hostname validated: ${name}"
}

# validate_password — validate password is non-empty and does not contain
# characters that would break heredoc injection
# Usage: validate_password <password> <field_name>
validate_password() {
    local pass="$1"
    local field="${2:-password}"
    if [[ -z "${pass}" ]]; then
        die "${field} cannot be empty"
    fi
    if (( ${#pass} < 4 )); then
        die "${field} too short (minimum 4 characters)"
    fi
    log "${field} validated (length ${#pass})"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  CHROOT HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

# safe_chroot — execute a command inside the chroot
# Copies globals.env into the chroot first so variables are available.
# Usage: safe_chroot <command_string>
safe_chroot() {
    local cmd="$1"
    local root="${GTLTSC_MOUNT_ROOT}"

    if ! findmnt -rn "${root}" &>/dev/null; then
        die "Cannot chroot: ${root} is not mounted"
    fi

    arch-chroot "${root}" /bin/bash -c "${cmd}"
}

# safe_chroot_script — execute a script inside the chroot
# Copies the script into the chroot, executes, then removes.
# Usage: safe_chroot_script <local_script_path>
safe_chroot_script() {
    local script="$1"
    local root="${GTLTSC_MOUNT_ROOT}"
    local script_name
    script_name="$(basename "${script}")"
    local chroot_script="/tmp/_gtltsc_${script_name}"

    cp "${script}" "${root}${chroot_script}"
    chmod +x "${root}${chroot_script}"
    arch-chroot "${root}" "${chroot_script}"
    rm -f "${root}${chroot_script}"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STAGE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

# set_stage — update the current stage name for logging/rollback
# Usage: set_stage "02-disk"
set_stage() {
    GTLTSC_CURRENT_STAGE="$1"
    log "═══════════════════════════════════════════════"
    log "  STAGE: ${GTLTSC_CURRENT_STAGE}"
    log "═══════════════════════════════════════════════"
}
