#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Base ISO — orchestrator
# =============================================================================
# WHAT
#   Runs the baseline construction scripts (01..06) in fixed order inside a
#   Cubic chroot on stock Ubuntu 24.04.
#
# WHY
#   Ordering matters: preflight (DNS + apt update + offline UFW) must land
#   before Plymouth pulls initramfs-tools transitively; GRUB depends on the
#   Plymouth theme being registered as default alternative; GDM branding
#   depends on the AccountsService templates being diverted first so the
#   first user creation does not re-attach a `.face` icon; sessions rename
#   is last because it only rewrites text files and depends on nothing.
#
# IDEMPOTENT: each sub-script is individually idempotent; re-running the
#   orchestrator on an already-branded chroot is safe.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"

STEPS=(
    "01-chroot-preflight.sh"
    "02-plymouth-install.sh"
    "03-grub-rebrand.sh"
    "04-gdm-branding.sh"
    "05-accountsservice-templates.sh"
    "06-sessions-rename-divert.sh"
)

echo "==> Aïobi OS — base ISO construction (${#STEPS[@]} steps)"

for step in "${STEPS[@]}"; do
    script="$HERE/$step"
    [ -x "$script" ] || { echo "ERROR: $script missing or not executable"; exit 1; }
    echo
    echo "==> [$(date +%H:%M:%S)] $step"
    "$script"
done

echo
echo "==> base ISO baseline complete — chroot ready for Cubic generate"
