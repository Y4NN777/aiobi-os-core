#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 10 — Snap final purge + APT pin
# ----------------------------------------------------------------------------
# Purpose : (a) purge residual snap data left in ~/snap after the base debloat
#           and the first-boot provisioning service have run;
#           (b) install /etc/apt/preferences.d/nosnap.pref with
#           Pin-Priority: -10 to block any future apt install pulling snapd
#           back in as a dependency.
#
# References
#   - Ubuntu MATE community guide on snap block:
#     https://ubuntu-mate.community/t/completely-remove-snap-and-prevent-it-from-ever-installing/28456
#
# Idempotent: rm -rf on ~/snap is safe; tee overwrites nosnap.pref;
# verification via apt-cache policy is idempotent.
#
# Ordering: standalone. Recommended late in the customization pipeline so it
# does not interfere with any snap-based install steps that may have been
# needed earlier in the build (Subiquity in older Ubuntu; not the case on
# 24.04).
# ============================================================================

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Must run as root (sudo)."; exit 1; }

RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

# --- 1. Purge user home residues ---------------------------------------------
# The base debloat step plus the first-boot aos-debloat.service remove snapd
# system-side, but per-user ~/snap/snapd-desktop-integration/ may remain as
# an empty directory.
if [[ -n "$RUN_USER" && "$RUN_USER" != "root" ]]; then
    USER_HOME=$(getent passwd "$RUN_USER" | cut -d: -f6)
    if [[ -d "${USER_HOME}/snap" ]]; then
        rm -rf "${USER_HOME}/snap"
        echo "  removed ${USER_HOME}/snap residue"
    fi
fi
# Also root's if any
[[ -d /root/snap ]] && rm -rf /root/snap

# Live-CD squashfs residue. The vanilla Ubuntu 24.04 live session runs
# snapd as the `ubuntu` user, which populates
# /home/ubuntu/snap/snapd-desktop-integration/ with a full runtime tree
# (font caches, GTK immodules, GIO modules). When Cubic captures the
# live squashfs, that tree is packed into the ISO and Subiquity replicates
# it into every freshly-created user home on install — visible on the
# installed system as `~/snap/snapd-desktop-integration/` even though
# no snapd process ever ran there.
#
# In a chroot the `ubuntu` user home may still be present; glob-purge
# everything under /home/*/snap AND remove the OEM live-CD user home
# entirely. Also purge /etc/skel/snap in case a future Ubuntu base image
# adds a skel stub for it.
rm -rf /home/*/snap 2>/dev/null || true
rm -rf /home/ubuntu 2>/dev/null || true
rm -rf /etc/skel/snap 2>/dev/null || true

# --- 2. APT pin — refuse snapd reinstall via dependency chain ----------------
tee /etc/apt/preferences.d/nosnap.pref > /dev/null << 'EOF'
# Aïobi OS — block snapd reinstallation via dependency chain.
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF
chmod 644 /etc/apt/preferences.d/nosnap.pref

# --- 3. Also pin the snap-related meta packages that could pull snapd back ---
tee -a /etc/apt/preferences.d/nosnap.pref > /dev/null << 'EOF'

Package: snap-confine
Pin: release a=*
Pin-Priority: -10

Package: snapd-desktop-integration
Pin: release a=*
Pin-Priority: -10
EOF

# --- 4. Purge stale apt cache so the new pin takes effect immediately -------
apt-get update -qq || true

# --- 5. Verification ---------------------------------------------------------
echo "== Verification =="
echo "== apt-cache policy snapd =="
apt-cache policy snapd 2>&1 | head -6
echo
echo "== residual /snap /var/snap /var/cache/snapd =="
for d in /snap /var/snap /var/cache/snapd; do
    if [[ -e "$d" ]]; then
        echo "  ⚠ $d STILL EXISTS — earlier debloat may be incomplete"
    else
        echo "  ✓ $d absent"
    fi
done
echo
echo "== residual ~/snap =="
if [[ -n "$RUN_USER" && "$RUN_USER" != "root" ]]; then
    if [[ -d "${USER_HOME}/snap" ]]; then
        echo "  ⚠ ${USER_HOME}/snap STILL EXISTS"
    else
        echo "  ✓ ${USER_HOME}/snap absent"
    fi
fi

echo "== 10-snap-final-purge.sh done =="
echo "Effect: any future 'apt install <pkg>' with snapd as a dependency will now be refused."
