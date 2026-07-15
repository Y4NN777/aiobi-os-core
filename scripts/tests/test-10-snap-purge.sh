#!/usr/bin/env bash
# =============================================================================
# Test — Step 10 — Snap final purge + APT pin + first-boot debloat service
# =============================================================================
# Snapd is deliberately KEPT in the chroot ISO because Subiquity is a snap —
# purging at build time kills installation. The actual purge is deferred to
# first boot via aos-debloat.service (a self-destructing systemd oneshot).
# On an installed VM post-first-boot, snapd + companions are gone and cannot
# reinstall (APT pin -10). This test covers BOTH horizons:
#   - chroot / pre-first-boot: aos-debloat.service + aos-debloat.sh must
#     be present and enabled, pin file must exist, no snapd assertion
#   - installed VM post-first-boot: snapd + telemetry companions absent,
#     dirs cleaned, no ~/snap residues
# The chroot vs installed-VM branch is chosen via /var/lib/aiobi-firstboot-done
# marker written by the first-boot service (both flavors of).
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 10 — Snap first-boot debloat installed + pin + residues gone"

# ----- Pin file (present in both horizons) --------------------------------
# (moved before the horizon split so both paths assert it)
PIN=/etc/apt/preferences.d/nosnap.pref
assert_file "$PIN"

# ----- First-boot debloat service + script (chroot + installed both) ------
# aos-debloat.service is shipped by step 10 and runs once at first user
# boot to purge snapd + telemetry companions (apport, whoopsie,
# ubuntu-report, popularity-contest, apport-symptoms). Must always be
# present on any Aïobi image.
assert_executable /usr/local/sbin/aos-debloat.sh
assert_systemd_unit /etc/systemd/system/aos-debloat.service
assert_grep /etc/systemd/system/aos-debloat.service "ExecStart=/usr/local/sbin/aos-debloat.sh"

# Enabled via systemctl OR direct symlink for chroot mode.
if [ -L /etc/systemd/system/multi-user.target.wants/aos-debloat.service ] \
   || systemctl is-enabled aos-debloat.service 2>/dev/null | grep -q enabled; then
    pass "aos-debloat.service enabled"
else
    fail "aos-debloat.service enabled" "no symlink and systemctl reports not enabled"
fi

# Script contains the six purge targets — this is the load-bearing contract
# that scripts/23 pin-file + this service purge match. Regressions in
# either list break the debloat.
for target in snapd ubuntu-report popularity-contest apport whoopsie apport-symptoms; do
    assert_grep /usr/local/sbin/aos-debloat.sh "$target"
done

# Live-CD guard must be present — running the purge inside Cubic's live
# session would break Subiquity mid-install.
assert_grep /usr/local/sbin/aos-debloat.sh "overlay"

# ----- Installed-VM horizon (skip on chroot) ------------------------------
# The absent-package + absent-dir checks only make sense once aos-debloat
# has run at least once. The marker file is written by every Aïobi
# first-boot oneshot; if it is absent we are almost certainly in chroot.
if [ ! -f /var/lib/aiobi-firstboot-done ]; then
    skip "snapd absent" "chroot mode — aos-debloat.service defers purge to first boot"
    skip "/snap absent" "chroot mode — aos-debloat.service defers purge to first boot"
    skip "/var/snap absent" "chroot mode — aos-debloat.service defers purge to first boot"
    skip "~/snap residues" "chroot mode — cleanup runs at first boot only"
    finalize
fi

assert_no_pkg snap
assert_no_pkg snapd
assert_no_pkg snap-confine
assert_no_pkg snapd-desktop-integration

assert_no_dir /snap
assert_no_dir /var/snap

# APT pin priority -10 on each snap package (pin file itself was asserted
# earlier so both horizons cover it).
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
