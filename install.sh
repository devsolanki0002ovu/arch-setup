#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# install.sh — God-Tier LTSC Provisioner Orchestrator
# ─────────────────────────────────────────────────────────────────────────────
# Master entry point. Sources all modules in sequence, manages rollback on
# failure, and produces a final summary.
#
# Usage: bash install.sh
#
# IMPORTANT: Run from the Arch Linux live ISO as root.
# ─────────────────────────────────────────────────────────────────────────────

set -Eeuo pipefail

# ── Resolve script directory (works from any CWD) ───────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Source configuration ────────────────────────────────────────────────────
# shellcheck source=globals.env
source "${SCRIPT_DIR}/globals.env"

# ── Source shared library ───────────────────────────────────────────────────
# shellcheck source=00-lib.sh
source "${SCRIPT_DIR}/00-lib.sh"

# ── Initialize logging ─────────────────────────────────────────────────────
_init_logging

# ═══════════════════════════════════════════════════════════════════════════════
#  TRAP HANDLER — ROLLBACK ON FAILURE
# ═══════════════════════════════════════════════════════════════════════════════

_install_success=false

_on_exit() {
    local exit_code=$?
    if [[ "${_install_success}" == "true" ]]; then
        return 0
    fi
    if (( exit_code != 0 )); then
        echo "" >&2
        printf '%b\n' "${_C_RED}════════════════════════════════════════════════════════════${_C_RESET}" >&2
        printf '%b\n' "${_C_RED}  INSTALLATION FAILED${_C_RESET}" >&2
        printf '%b\n' "${_C_RED}  Stage:     ${GTLTSC_CURRENT_STAGE}${_C_RESET}" >&2
        printf '%b\n' "${_C_RED}  Exit Code: ${exit_code}${_C_RESET}" >&2
        printf '%b\n' "${_C_RED}  Log:       ${GTLTSC_LOG_FILE}${_C_RESET}" >&2
        printf '%b\n' "${_C_RED}════════════════════════════════════════════════════════════${_C_RESET}" >&2
        rollback "${exit_code}"
    fi
}

trap _on_exit EXIT

# ═══════════════════════════════════════════════════════════════════════════════
#  BANNER
# ═══════════════════════════════════════════════════════════════════════════════

cat <<'BANNER'

  ╔═══════════════════════════════════════════════════════════╗
  ║                                                           ║
  ║     GOD-TIER LTSC PROVISIONER                             ║
  ║     Arch Linux Enterprise Deployment Framework            ║
  ║                                                           ║
  ║     Target: Pentium G2010 / GeForce 210 / 4GB DDR3       ║
  ║     Desktop: LXQt + Openbox (X11)                         ║
  ║     Theme: Ultra-dark Cyberpunk                           ║
  ║                                                           ║
  ╚═══════════════════════════════════════════════════════════╝

BANNER

log "God-Tier LTSC Provisioner starting..."
log "Log file: ${GTLTSC_LOG_FILE}"

# ═══════════════════════════════════════════════════════════════════════════════
#  STAGE EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

# Each stage is sourced (not subshelled) to share state between stages.
# The set -e flag in strict mode means any failure will trigger the EXIT trap.

# ── Stage 1: Preflight ──────────────────────────────────────────────────────
log "Loading stage: 01-preflight"
# shellcheck source=01-preflight.sh
source "${SCRIPT_DIR}/01-preflight.sh"

# ── Stage 2: Disk ───────────────────────────────────────────────────────────
log "Loading stage: 02-disk"
# shellcheck source=02-disk.sh
source "${SCRIPT_DIR}/02-disk.sh"

# ── Stage 3: Pacstrap ───────────────────────────────────────────────────────
log "Loading stage: 03-pacstrap"
# shellcheck source=03-pacstrap.sh
source "${SCRIPT_DIR}/03-pacstrap.sh"

# ── Stage 4: Core Configuration ─────────────────────────────────────────────
log "Loading stage: 04-core"
# shellcheck source=04-core.sh
source "${SCRIPT_DIR}/04-core.sh"

# ── Stage 5: GUI Configuration ──────────────────────────────────────────────
log "Loading stage: 05-gui"
# shellcheck source=05-gui.sh
source "${SCRIPT_DIR}/05-gui.sh"

# ── Stage 6: Validation ─────────────────────────────────────────────────────
log "Loading stage: 06-validate"
# shellcheck source=06-validate.sh
source "${SCRIPT_DIR}/06-validate.sh"

# ═══════════════════════════════════════════════════════════════════════════════
#  COMPLETION
# ═══════════════════════════════════════════════════════════════════════════════

_install_success=true

echo ""
echo "═══════════════════════════════════════════════════════════════════"
printf '%b\n' "${_C_GREEN}  ✓ INSTALLATION COMPLETE${_C_RESET}"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "  System Summary:"
echo "    Hostname:  ${GTLTSC_HOSTNAME}"
echo "    Username:  ${GTLTSC_USERNAME}"
echo "    Desktop:   LXQt + Openbox"
echo "    Theme:     ${GTLTSC_GTK_THEME} / ${GTLTSC_ICON_THEME}"
echo "    Kernel:    linux-lts"
echo "    Boot:      GRUB (UEFI removable)"
echo ""
echo "  Performance Tuning:"
echo "    ZRAM:      ${GTLTSC_ZRAM_SIZE_PERCENT}% RAM (${GTLTSC_ZRAM_ALGORITHM})"
echo "    Scheduler: BFQ (HDD)"
echo "    Swappiness: ${GTLTSC_SWAPPINESS}"
echo "    EarlyOOM:  Enabled"
echo ""
echo "  Next Steps:"
echo "    1. Review the validation report above"
echo "    2. Unmount:  umount -R ${GTLTSC_MOUNT_ROOT}"
echo "    3. Reboot:   reboot"
echo "    4. Log in at the SDDM screen"
echo ""
echo "  Log saved to: ${GTLTSC_LOG_FILE}"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

log "Installation finished successfully"
