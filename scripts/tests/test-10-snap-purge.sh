#!/usr/bin/env bash
# =============================================================================
# Test — Step 10 — Snap final purge + APT pin
# =============================================================================
# Verifies that snap and snapd are fully absent from the installed system:
# no package, no /snap or /var/snap directories, no user home residues,
# no ubuntu OEM home, no skel stub. Also confirms the nosnap.pref APT pin
# blocks the three metapackages that could pull snapd back in.
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 10 — Snap purged and APT-pinned out"

assert_no_pkg snap
assert_no_pkg snapd
assert_no_pkg snap-confine
assert_no_pkg snapd-desktop-integration

assert_no_dir /snap
assert_no_dir /var/snap

# APT pin file present with priority -10 on each snap package.
PIN=/etc/apt/preferences.d/nosnap.pref
assert_file "$PIN"
if [ -f "$PIN" ]; then
    for pkg in snapd snap-confine snapd-desktop-integration; do
        if awk -v p="$pkg" '
            /^Package:/ {cur = $2}
            /^Pin-Priority:/ && cur == p && $2 == "-10" {found = 1; exit}
            END {exit found ? 0 : 1}
        ' "$PIN"; then
            pass "APT pin -10 for $pkg present"
        else
            fail "APT pin -10 for $pkg present" "block missing or wrong priority"
        fi
    done
fi

# User-home residues and OEM live-CD account: must all be gone.
if compgen -G "/home/*/snap" >/dev/null; then
    fail "no /home/*/snap residues" "found leftover per-user snap dirs"
else
    pass "no /home/*/snap residues"
fi
assert_no_dir /home/ubuntu
assert_no_dir /etc/skel/snap

finalize
