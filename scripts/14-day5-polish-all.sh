#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — US-1.4/1.5/1.6 Day 5 all-in-one orchestrator
# =============================================================================
# Purpose : run every US-1.4/1.5/1.6 script in the correct dependency order
#           for a fresh chroot Cubic re-repack pass. Suitable for one-shot
#           Cubic Generate preparation — copy this scripts/ directory into
#           the chroot terminal, `bash 14-day5-polish-all.sh`, then Cubic
#           Generate the ISO.
#
# References :
#   - Log 5 §5 Issue 36 (ISO bootloader dead-end via linux-live-kit → pivot
#     to Cubic re-repack, this orchestrator prepared for that)
#   - Log 5 §5 Issue 37 (documentation-before-packaging discipline)
#
# Ordering rationale :
#   01 install-extensions            → dash-to-panel + gnome-shell-extensions
#   02 configure-panel               → dconf keyfile shipped
#   03 inject-theme (V2 REWRITE)     → Aïobi GTK theme (full Yaru clone + sed)
#   04 install-icons                 → Papirus + Papirus-Dark + Aïobi placeholders
#   05 rebrand-os                    → os-release + hostname + GRUB + MOTD + first-boot service
#   08 inject-shell-theme            → Aïobi gnome-shell theme (needs 01's user-theme)
#   09 terminal-profile              → gnome-terminal Aïobi palette
#   10 snap-final-purge              → APT pin nosnap (US-1.1 close)
#   11 apt-brand-alias               → mirror.aiobi.local (DEB822 + /etc/hosts)
#   12 wine-proton-install           → US-1.5 Wine + Proton + MIME
#   13 productivity-stack            → US-1.6 OnlyOffice + Brave + VLC + Flameshot + PeaZip + AppFlowy
#   06 apply-persistence             → dconf locks + skel — LAST because it seals state
#   07 validate-us14                 → PASS/FAIL final check
#
# Chroot mode note : some steps that require a live D-Bus session (gnome-
# extensions enable, dconf writes to per-user) are silently skipped inside
# a chroot terminal. The system dconf keyfiles + first-boot services still
# ship — they activate at first user login on the installed ISO.
#
# Idempotent : each individual script is idempotent (backup on first run,
# restore-from-backup on subsequent). Re-running this orchestrator is safe.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
LOG="/var/log/aiobi-day5-polish-all.log"

echo "==> Aïobi Day 5 polish all-in-one — logging to $LOG"
echo "==> Started: $(date -u +%FT%TZ)" | tee -a "$LOG"

run_step() {
    local step="$1"
    local script="$HERE/$step"
    if [ ! -x "$script" ]; then
        echo "SKIP (not found or not executable): $step" | tee -a "$LOG"
        return 0
    fi
    echo "" | tee -a "$LOG"
    echo "==== STEP: $step ====" | tee -a "$LOG"
    if bash "$script" 2>&1 | tee -a "$LOG"; then
        echo "  ✓ $step OK" | tee -a "$LOG"
    else
        local rc=$?
        echo "  ✗ $step FAILED (exit $rc)" | tee -a "$LOG"
        echo "See $LOG for full trail. Halting pipeline." | tee -a "$LOG"
        exit $rc
    fi
}

# Setup phase — GNOME extensions + panel config + themes + icons + rebrand
run_step 01-install-extensions.sh
run_step 02-configure-panel.sh
run_step 03-inject-theme.sh
run_step 04-install-icons.sh
run_step 05-rebrand-os.sh

# Polish phase — Day 5 visual + brand additions
run_step 08-inject-shell-theme.sh
run_step 09-terminal-profile.sh
run_step 10-snap-final-purge.sh
run_step 11-apt-brand-alias.sh

# Interop + productivity — closes US-1.5 + US-1.6 milestone S1 CA-4 + CA-5
run_step 12-wine-proton-install.sh
run_step 13-productivity-stack.sh

# Persistence LAST — seals dconf state, /etc/skel populated
run_step 06-apply-persistence.sh

# Validation
run_step 07-validate-us14.sh

echo "" | tee -a "$LOG"
echo "==> Aïobi Day 5 polish all-in-one FINISHED: $(date -u +%FT%TZ)" | tee -a "$LOG"
echo "    Full log: $LOG"
echo ""
echo "Next steps :"
echo "  1. Review any FAIL lines in the validation output above."
echo "  2. If chroot mode: continue Cubic → Next → Generate."
echo "  3. If installed VM: logout+login to see the shell theme + fonts + palette."
