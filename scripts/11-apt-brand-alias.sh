#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — soft-brand mirror alias — /etc/hosts + DEB822 rewrite
# ----------------------------------------------------------------------------
# Purpose : rewrite the Ubuntu apt mirror hostnames in output ONLY (URIs shown
#           in `apt update`, `apt install`, etc.) from `bf.archive.ubuntu.com`
#           and `security.ubuntu.com` to `mirror.aiobi.local` and
#           `security.aiobi.local`, mapped in /etc/hosts to the real Canonical
#           IPs. Cosmetic alias — Canonical infrastructure (IPs, repo path)
#           preserved.
#
# Solves  : Log 5 §2.12 — Ubuntu-branded hostnames were visible in every
#           apt output despite full display-layer rebrand. Running our own
#           packages.aiobi.com mirror is out of MVP scope; DNS-alias soft-brand
#           is the pragmatic middle ground.
#
# References :
#   - Log 5 §2.12 (fix documented)
#   - Log 5 §4.3 (brand-identity vs platform-identity separation rationale)
#   - Log 5 §5 Issue 27 (Ubuntu 24.04 DEB822 sources format)
#   - Log 5 §5 Issue 28 (IPv6 unreachable in NAT-only VM)
#
# Idempotent: /etc/hosts entries removed if present before re-adding; sed
# rewrite of ubuntu.sources is idempotent via bak-restore pattern.
#
# Fragility caveat: Canonical rotates round-robin IPs on their mirrors. If the
# IPs pinned in /etc/hosts disappear from Canonical DNS, apt breaks until
# re-resolved. V1.1 planned improvement: local dnsmasq CNAME OR first-boot
# service re-resolves + rewrites /etc/hosts on each boot.
#
# Ordering: standalone. Run any time after 04-install-icons.sh (which uses
# apt heavily and would be confused by mid-run alias switching). Recommended:
# after all apt-based install scripts (04, 06, 12, 13) — as a final cosmetic pass.
# ============================================================================

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Must run as root (sudo)."; exit 1; }

# --- 1. Resolve real Canonical IPv4 addresses --------------------------------
# Force IPv4: getent hosts returns IPv6 first in mixed-DNS zones. IPv6 is
# unreachable in NAT-only virt-manager VM (Issue 28).
BF_IPV4=$(getent ahostsv4 bf.archive.ubuntu.com 2>/dev/null | awk 'NR==1{print $1}')
SEC_IPV4=$(getent ahostsv4 security.ubuntu.com 2>/dev/null | awk 'NR==1{print $1}')

if [[ -z "$BF_IPV4" ]] || [[ -z "$SEC_IPV4" ]]; then
    echo "ERROR: could not resolve Canonical mirror IPs. Network unreachable?"
    echo "  bf.archive.ubuntu.com  → ${BF_IPV4:-FAIL}"
    echo "  security.ubuntu.com    → ${SEC_IPV4:-FAIL}"
    exit 4
fi
echo "  Canonical mirror BF (v4):  $BF_IPV4"
echo "  Canonical security (v4):   $SEC_IPV4"

# --- 2. /etc/hosts alias — remove old + add new -----------------------------
# Idempotent: kill any prior aiobi.local entries then append fresh.
sed -i '/aiobi\.local/d' /etc/hosts
tee -a /etc/hosts > /dev/null << EOF
# Aïobi OS — soft-brand apt mirror alias (Ubuntu infra preserved)
# Managed by 11-apt-brand-alias.sh — do not edit manually.
${BF_IPV4}  mirror.aiobi.local
${SEC_IPV4} security.aiobi.local
EOF

# --- 3. Rewrite DEB822 ubuntu.sources ---------------------------------------
# Ubuntu 24.04 migrated apt sources from legacy `/etc/apt/sources.list` (deb URI
# SUITE COMPONENTS lines) to DEB822 format at `/etc/apt/sources.list.d/ubuntu.sources`
# (Types:/URIs:/Suites:/Components:/Signed-By: blocks). Sed the URIs field.
UBUNTU_SOURCES=/etc/apt/sources.list.d/ubuntu.sources
if [[ -f "$UBUNTU_SOURCES" ]]; then
    [[ -f "${UBUNTU_SOURCES}.aiobi.bak" ]] || cp "$UBUNTU_SOURCES" "${UBUNTU_SOURCES}.aiobi.bak"
    # Always sed from backup to preserve idempotency
    sed \
        -e 's|bf\.archive\.ubuntu\.com|mirror.aiobi.local|g' \
        -e 's|security\.ubuntu\.com|security.aiobi.local|g' \
        "${UBUNTU_SOURCES}.aiobi.bak" > "$UBUNTU_SOURCES"
    echo "  rewrote $UBUNTU_SOURCES"
fi

# --- 4. Also cover legacy sources.list if any (older Ubuntu installs) --------
if [[ -f /etc/apt/sources.list ]] && grep -q "ubuntu\.com" /etc/apt/sources.list; then
    [[ -f /etc/apt/sources.list.aiobi.bak ]] || cp /etc/apt/sources.list /etc/apt/sources.list.aiobi.bak
    sed -i \
        -e 's|bf\.archive\.ubuntu\.com|mirror.aiobi.local|g' \
        -e 's|security\.ubuntu\.com|security.aiobi.local|g' \
        /etc/apt/sources.list
    echo "  rewrote legacy /etc/apt/sources.list"
fi

# --- 5. Refresh apt caches so the alias takes effect immediately -------------
apt-get update -qq

# --- 6. Verification ---------------------------------------------------------
echo
echo "== Verification — apt update output (first 8 lines) =="
apt-get update 2>&1 | head -8
echo
echo "== /etc/hosts aiobi.local entries =="
grep aiobi\.local /etc/hosts || true

echo "== 11-apt-brand-alias.sh done =="
echo "Effect: all apt operations now display mirror.aiobi.local instead of bf.archive.ubuntu.com."
