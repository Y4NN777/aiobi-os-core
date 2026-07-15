#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — customization pipeline orchestrator
# =============================================================================
# Purpose : run every customization script in the correct dependency order
#           for a fresh chroot pass under Cubic. Copy this scripts/ directory
#           into the chroot terminal, run `bash run-all.sh`, then let
#           Cubic generate the ISO.
#
# Ordering rationale
#   01 install-extensions              dash-to-panel + gnome-shell-extensions
#   02 configure-panel                 dconf keyfile shipped
#   03 inject-theme                    Aïobi GTK theme (Yaru clone + sed)
#   04 install-icons                   Papirus + Papirus-Dark + Aïobi placeholders
#   05 rebrand-os                      os-release + hostname + GRUB + MOTD + first-boot
#   08 inject-shell-theme              Aïobi gnome-shell theme (needs 01's user-theme)
#   10 snap-final-purge                APT pin nosnap + residue cleanup
#   11 apt-brand-alias                 mirror.aiobi.local (DEB822 + /etc/hosts)
#   12 wine-proton-install             Wine + GE-Proton + MIME associations
#   13 productivity-stack              OnlyOffice + Brave + VLC + Flameshot + Flatpaks
#   15 install-ollama                  Ollama daemon + first-boot model pull (loopback)
#   17 install-aiobi-term              aiobi-term CLI + knowledge package + shell integration
#   18 install-anythingllm             AnythingLLM Desktop AppImage
#   19 tune-ram                        zRAM swap + Ollama socket activation
#   20 ai-firewall                     iptables/ip6tables OUTPUT REJECT :11434 non-loopback
#   21 configure-bash-completion       TAB menu-complete + argcomplete + skel setup
#   22 taskbar-desktop-defaults        Ding install + taskbar pins + skel/Desktop
#   06 apply-persistence               dconf locks + skel + fonts — LAST (seals state)
#   09 terminal-profile                gnome-terminal Aïobi palette (verifies compiled db)
#      validate                        harness over scripts/tests/*.sh (no numeric
#                                      prefix — it is a meta-tool, not a step)
#
# The orchestrator itself has no numeric prefix on purpose — it is not
# a step, it is the entry point that chains the steps above. The same
# rationale applies to validate.sh (the test-suite harness).
#
# Chroot mode note : steps that require a live D-Bus session (gnome-
# extensions enable, dconf writes to per-user) are silently skipped inside
# a chroot terminal. The system dconf keyfiles + first-boot services still
# ship and activate at first user login on the installed ISO.
#
# Idempotent : each individual script is idempotent (backup on first run,
# restore-from-backup on subsequent). Re-running this orchestrator is safe.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
LOG="/var/log/aiobi-run-all.log"

echo "==> Aïobi customization pipeline — logging to $LOG"
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

# Polish phase — shell theme + snap purge + apt alias
run_step 08-inject-shell-theme.sh
run_step 10-snap-final-purge.sh
run_step 11-apt-brand-alias.sh

# Interoperability + productivity applications
run_step 12-wine-proton-install.sh
run_step 13-productivity-stack.sh

# AI layer — Ollama daemon, CLI, GUI, memory tuning
run_step 15-install-ollama.sh
run_step 17-install-aiobi-term.sh
run_step 18-install-anythingllm.sh
run_step 19-tune-ram.sh
run_step 20-ai-firewall.sh

# UX layer — terminal auto-completion (TAB menu-complete + Shift+TAB backward
# + argcomplete). Written into /etc/skel/.bashrc so it lands in every future
# user's shell. Placed before 06-apply-persistence.sh because 06 copies skel
# into the sealed image state.
run_step 21-configure-bash-completion.sh

# UX layer — Windows-familiar defaults: install Ding for desktop icons,
# preseed taskbar pins (org.gnome.shell favorite-apps) + Ding config +
# a curated set of .desktop shortcuts in /etc/skel/Desktop/. Placed
# before 06 because it writes a dconf keyfile 06 will compile.
run_step 22-taskbar-desktop-defaults.sh

# Persistence — dconf profile + keyfiles (branding, wallpaper, panel, terminal)
# + locks + /etc/skel. This step installs every system dconf keyfile and
# compiles the local db, so 09-terminal-profile.sh (verification only) can
# read from the compiled db afterwards.
run_step 06-apply-persistence.sh

# Verify the terminal palette landed in the compiled dconf db
run_step 09-terminal-profile.sh

# Validation of the full milestone criteria — harness over scripts/tests/*.sh
# (unnumbered on purpose: meta-tool, not a pipeline step).
run_step validate.sh

echo "" | tee -a "$LOG"
echo "==> Aïobi customization pipeline FINISHED: $(date -u +%FT%TZ)" | tee -a "$LOG"
echo "    Full log: $LOG"
echo ""
echo "Next steps :"
echo "  1. Review any FAIL lines in the validation output above."
echo "  2. If chroot mode: continue Cubic → Next → Generate."
echo "  3. If installed VM: logout+login to see the shell theme + fonts + palette."
