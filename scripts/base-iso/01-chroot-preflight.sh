#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Base ISO — Step 01 — Chroot pre-flight
# =============================================================================
# WHAT
#   1. Repair DNS resolution inside the Cubic chroot so subsequent `apt`
#      calls can reach the Ubuntu mirrors. Cubic's chroot inherits a broken
#      /etc/resolv.conf symlink pointing at a systemd stub file that does
#      not exist in the chroot context.
#   2. Refresh the APT index once so downstream scripts can install packages
#      without each re-triggering an update.
#   3. Apply the offline UFW configuration (default policies + boot-time
#      activation) via `sed` on the config files — `ufw enable` cannot run
#      in the chroot because there is no systemd D-Bus.
#
# WHY
#   Every subsequent script in this pipeline installs at least one package
#   (initramfs-tools, glib-compile-resources, plymouth-themes...) or
#   modifies vendor configuration; without DNS + refreshed cache they all
#   fail at the first `apt-get install` call. UFW is applied here rather
#   than in a dedicated step because the offline recipe is three `sed`
#   invocations and belongs with the "make the chroot usable" step.
#
# SOURCES
#   - https://help.ubuntu.com/community/CustomizeLiveCD (Cubic chroot DNS)
#   - https://help.ubuntu.com/community/UFW
#   - https://manpages.ubuntu.com/manpages/noble/en/man5/resolv.conf.5.html
#
# IDEMPOTENT: mkdir/tee/ln overwrite; sed patterns are anchored so a re-run
#   leaves the file unchanged after the first pass.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi — 01-chroot-preflight.sh"

# ----- 1) Fix DNS resolution -------------------------------------------------
# The stock chroot ships /etc/resolv.conf as a symlink into a systemd-resolved
# runtime path that does not exist. Recreate the target file with a working
# nameserver and re-anchor the stub symlink so any process that follows it
# still finds a resolver.
echo "  fixing chroot DNS resolution"
mkdir -p /run/systemd/resolve
cat > /run/systemd/resolve/resolv.conf << 'EOF'
nameserver 127.0.1.1
search network
EOF
ln -srf /run/systemd/resolve/resolv.conf /run/systemd/resolve/stub-resolv.conf

# Some Cubic chroots also carry a dangling /etc/resolv.conf symlink — force
# it to point at a resolvable file so `apt` and `curl` do not fail on
# name-resolution before they ever open a socket.
if [ ! -e /etc/resolv.conf ] || [ -L /etc/resolv.conf ]; then
    ln -srf /run/systemd/resolve/resolv.conf /etc/resolv.conf
fi

# ----- 2) Refresh APT index --------------------------------------------------
echo "  refreshing APT index (once for the whole pipeline)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# ----- 3) UFW offline configuration ------------------------------------------
# Install ufw first if missing (stock desktop has it, but the chroot can be
# minimised) — the actual activation is deferred to first boot via the
# ENABLED=yes flag in /etc/ufw/ufw.conf.
if ! command -v ufw >/dev/null 2>&1; then
    echo "  installing ufw"
    apt-get install -y ufw
fi

echo "  applying UFW default policies (DROP inbound + forward)"
sed -i 's/^DEFAULT_INPUT_POLICY=.*/DEFAULT_INPUT_POLICY="DROP"/'   /etc/default/ufw
sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="DROP"/' /etc/default/ufw

echo "  enabling UFW at boot (offline flag flip — no systemd required)"
sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf

# ----- 4) Verification -------------------------------------------------------
echo
echo "  Verification:"
printf "    DNS test: "
getent hosts archive.ubuntu.com >/dev/null 2>&1 && echo "OK" || echo "FAIL"
printf "    UFW ENABLED           = "; grep -E '^ENABLED=' /etc/ufw/ufw.conf
printf "    DEFAULT_INPUT_POLICY  = "; grep -E '^DEFAULT_INPUT_POLICY='   /etc/default/ufw
printf "    DEFAULT_FORWARD_POLICY= "; grep -E '^DEFAULT_FORWARD_POLICY=' /etc/default/ufw

echo "==> 01 done"
