#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — US-1.1 close — snap final purge + APT pin
# ----------------------------------------------------------------------------
# Purpose : (a) purge residual snap data left in ~/snap after Day 1 debloat +
#           first-boot service ran; (b) install /etc/apt/preferences.d/nosnap.pref
#           with Pin-Priority: -10 to block any future apt install pulling
#           snapd back in as a dependency.
#
# Closes  : US-1.1 CA-3 (APT Pinning to block Snap reinstallation).
#
# References :
#   - Log 5 §2.9 (this fix documented)
#   - Log 1 (Day 1 debloat baseline)
#   - Ubuntu MATE community guide on snap block
#     https://ubuntu-mate.community/t/completely-remove-snap-and-prevent-it-from-ever-installing/28456
#
# Idempotent: rm -rf on ~/snap is safe; tee overwrites nosnap.pref; verification
# via apt-cache policy is idempotent.
#
# Ordering: standalone. Can run any time. Recommended late in the Day 5 pipeline
# so it doesn't interfere with any snap-based install steps (if we ever need
# snapd temporarily during build for e.g. Subiquity — Ubuntu 24.04 doesn't).
# ============================================================================

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Must run as root (sudo)."; exit 1; }

RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

# --- 1. Purge user home residues ---------------------------------------------
# Day 1 debloat + first-boot aos-debloat.service removes snapd system-side,
# but per-user ~/snap/snapd-desktop-integration/ may remain as an empty dir.
if [[ -n "$RUN_USER" && "$RUN_USER" != "root" ]]; then
    USER_HOME=$(getent passwd "$RUN_USER" | cut -d: -f6)
    if [[ -d "${USER_HOME}/snap" ]]; then
        rm -rf "${USER_HOME}/snap"
        echo "  removed ${USER_HOME}/snap residue"
    fi
fi
# Also root's if any
[[ -d /root/snap ]] && rm -rf /root/snap

# --- 2. APT pin — refuse snapd reinstall via dependency chain ----------------
tee /etc/apt/preferences.d/nosnap.pref > /dev/null << 'EOF'
# Aïobi OS — block snapd reinstallation via dependency chain
# US-1.1 CA-3 (Log 5 §2.9). See also Log 1 for Day 1 debloat baseline.
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
        echo "  ⚠ $d STILL EXISTS — Day 1 debloat may be incomplete"
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
