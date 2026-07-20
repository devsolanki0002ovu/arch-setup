#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 01-preflight.sh — Environment Validation & Input Collection
# ─────────────────────────────────────────────────────────────────────────────
# Validates that we are in a suitable environment (UEFI, root, network, live
# ISO) and that all required packages exist in the repositories.
# Collects user identity interactively if not pre-configured.
#
# Depends on: globals.env, 00-lib.sh
# ─────────────────────────────────────────────────────────────────────────────

set_stage "01-preflight"

# ═══════════════════════════════════════════════════════════════════════════════
#  ENVIRONMENT CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

require_root
require_uefi
require_network

# Verify we are on a live ISO (archiso detection)
log "Checking for live ISO environment..."
if [[ ! -d /run/archiso ]] && [[ ! -f /etc/arch-release ]]; then
    warn "No /run/archiso detected. Proceeding, but this may not be a live ISO."
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  INTERACTIVE INPUT COLLECTION
# ═══════════════════════════════════════════════════════════════════════════════

# Prompt helper — reads user input with a default value
# Usage: prompt_value <variable_name> <prompt_text> <default_value> [is_password]
prompt_value() {
    local var_name="$1"
    local prompt_text="$2"
    local default_val="$3"
    local is_password="${4:-false}"

    # If already set (non-empty), skip
    local current_val="${!var_name:-}"
    if [[ -n "${current_val}" ]]; then
        log "${var_name} already set, skipping prompt"
        return 0
    fi

    local input=""
    if [[ "${is_password}" == "true" ]]; then
        while true; do
            printf '%b' "${_C_CYAN}? ${prompt_text}: ${_C_RESET}" >&2
            read -rs input
            printf '\n' >&2
            if [[ -z "${input}" && -n "${default_val}" ]]; then
                input="${default_val}"
            fi

            printf '%b' "${_C_CYAN}? Confirm ${prompt_text}: ${_C_RESET}" >&2
            local confirm=""
            read -rs confirm
            printf '\n' >&2

            if [[ "${input}" == "${confirm}" ]]; then
                break
            fi
            warn "Entries do not match. Please try again."
        done
    else
        local default_display=""
        if [[ -n "${default_val}" ]]; then
            default_display=" [${default_val}]"
        fi
        printf '%b' "${_C_CYAN}? ${prompt_text}${default_display}: ${_C_RESET}" >&2
        read -r input
        if [[ -z "${input}" && -n "${default_val}" ]]; then
            input="${default_val}"
        fi
    fi

    if [[ -z "${input}" ]]; then
        die "${var_name} is required but was left empty"
    fi

    # Use printf '%q' to safely escape the value
    printf -v "${var_name}" '%s' "${input}"
}

# Collect identity
log "Collecting system identity..."
prompt_value GTLTSC_HOSTNAME "Hostname" "archltsc"
validate_hostname "${GTLTSC_HOSTNAME}"

prompt_value GTLTSC_USERNAME "Username" ""
validate_username "${GTLTSC_USERNAME}"

prompt_value GTLTSC_USER_DISPLAY "Display name for ${GTLTSC_USERNAME}" "${GTLTSC_USERNAME}"

prompt_value GTLTSC_USER_PASSWORD "Password for ${GTLTSC_USERNAME}" "" true
validate_password "${GTLTSC_USER_PASSWORD}" "User password"

prompt_value GTLTSC_ROOT_PASSWORD "Root password" "" true
validate_password "${GTLTSC_ROOT_PASSWORD}" "Root password"

# ═══════════════════════════════════════════════════════════════════════════════
#  TARGET DISK SELECTION
# ═══════════════════════════════════════════════════════════════════════════════

if [[ -z "${GTLTSC_TARGET_DISK}" ]]; then
    log "Available block devices:"
    echo "" >&2
    lsblk -dno NAME,SIZE,TYPE,MODEL | grep -E "disk" | while IFS= read -r line; do
        printf '  %s\n' "${line}" >&2
    done
    echo "" >&2

    prompt_value GTLTSC_TARGET_DISK "Target disk (e.g. /dev/sda)" ""
fi

# Validate target disk
if [[ ! -b "${GTLTSC_TARGET_DISK}" ]]; then
    die "Target disk does not exist or is not a block device: ${GTLTSC_TARGET_DISK}"
fi

# Warn if disk has existing partitions
local_part_count=$(lsblk -nro NAME "${GTLTSC_TARGET_DISK}" 2>/dev/null | wc -l)
if (( local_part_count > 1 )); then
    warn "Target disk ${GTLTSC_TARGET_DISK} has existing partitions!"
    printf '%b' "${_C_YELLOW}  ALL DATA WILL BE DESTROYED. Continue? [y/N]: ${_C_RESET}" >&2
    local confirm_wipe=""
    read -r confirm_wipe
    if [[ "${confirm_wipe}" != "y" && "${confirm_wipe}" != "Y" ]]; then
        die "Aborted by user"
    fi
fi

# Verify disk is not the boot disk
local_boot_disk=$(findmnt -nro SOURCE / 2>/dev/null | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//' || true)
if [[ "${GTLTSC_TARGET_DISK}" == "${local_boot_disk}" ]]; then
    die "Target disk ${GTLTSC_TARGET_DISK} appears to be the running system's boot disk. Refusing."
fi

log "Target disk accepted: ${GTLTSC_TARGET_DISK}"

# ═══════════════════════════════════════════════════════════════════════════════
#  LOCALIZATION DEFAULTS
# ═══════════════════════════════════════════════════════════════════════════════

prompt_value GTLTSC_TIMEZONE "Timezone" "Asia/Kolkata"
if [[ ! -f "/usr/share/zoneinfo/${GTLTSC_TIMEZONE}" ]]; then
    die "Invalid timezone: ${GTLTSC_TIMEZONE}"
fi

prompt_value GTLTSC_LOCALE "Locale" "en_US.UTF-8"
prompt_value GTLTSC_KEYMAP "Keymap" "us"

# ═══════════════════════════════════════════════════════════════════════════════
#  PACMAN KEYRING INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

log "Initializing pacman keyring..."
pacman-key --init
pacman-key --populate archlinux
log "Pacman keyring initialized"

# ═══════════════════════════════════════════════════════════════════════════════
#  MIRROR SYNC & DATABASE REFRESH
# ═══════════════════════════════════════════════════════════════════════════════

log "Syncing pacman database..."
retry "${GTLTSC_RETRY_COUNT}" "${GTLTSC_RETRY_DELAY}" pacman -Sy --noconfirm
log "Pacman database synced"

# ═══════════════════════════════════════════════════════════════════════════════
#  PACKAGE AVAILABILITY PRE-CHECK
# ═══════════════════════════════════════════════════════════════════════════════

log "Verifying all required packages exist in repositories..."
_pkg_missing=()

for pkg in "${GTLTSC_ALL_PACKAGES[@]}"; do
    if ! pacman -Si "${pkg}" &>/dev/null; then
        _pkg_missing+=("${pkg}")
        warn "Package not found in repos: ${pkg}"
    fi
done

if (( ${#_pkg_missing[@]} > 0 )); then
    die "The following ${#_pkg_missing[@]} packages are not available in official repositories: ${_pkg_missing[*]}"
fi

log "All ${#GTLTSC_ALL_PACKAGES[@]} packages verified available"

# ═══════════════════════════════════════════════════════════════════════════════
#  PREFLIGHT COMPLETE
# ═══════════════════════════════════════════════════════════════════════════════

log "Preflight summary:"
log "  Hostname:    ${GTLTSC_HOSTNAME}"
log "  Username:    ${GTLTSC_USERNAME}"
log "  Display:     ${GTLTSC_USER_DISPLAY}"
log "  Timezone:    ${GTLTSC_TIMEZONE}"
log "  Locale:      ${GTLTSC_LOCALE}"
log "  Keymap:      ${GTLTSC_KEYMAP}"
log "  Target Disk: ${GTLTSC_TARGET_DISK}"
log "  Packages:    ${#GTLTSC_ALL_PACKAGES[@]} verified"
log "Preflight checks passed ✓"
