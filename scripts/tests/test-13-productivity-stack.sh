#!/usr/bin/env bash
# =============================================================================
# Test — Step 13 — Productivity stack
# =============================================================================
# Verifies the Aïobi-picked productivity apps are present:
#   dpkg  : OnlyOffice, Brave, VLC, Flameshot
#   flatpak: PeaZip, Obsidian
# Verifies the purged apps are ABSENT:
#   dpkg  : LibreOffice, Rhythmbox, Shotwell, Transmission
#   flatpak: AppFlowy (dropped — cloud onboarding conflicts with zero-data-leak)
# Verifies the documented retention apps are STILL PRESENT:
#   dpkg  : evolution-data-server, deja-dup, remmina, simple-scan
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 13 — productivity stack shipped, redundant defaults purged"

# ----- Installed (dpkg) ------------------------------------------------------
assert_pkg onlyoffice-desktopeditors
assert_pkg brave-browser
assert_pkg vlc
assert_pkg flameshot

# ----- Installed (flatpak) — skip cleanly on a base without flatpak ---------
if command -v flatpak >/dev/null 2>&1; then
    assert_flatpak io.github.peazip.PeaZip
    assert_flatpak md.obsidian.Obsidian
    # AppFlowy explicitly dropped.
    assert_no_flatpak com.appflowy.AppFlowy
else
    skip "flatpak-installed apps (PeaZip, Obsidian, no AppFlowy)" \
         "flatpak not installed on this host"
fi

# ----- Purged (dpkg) — the Ubuntu 24.04 defaults script 13 removes -----------
# LibreOffice: the core meta packages must be gone.
for pkg in libreoffice-core libreoffice-common libreoffice-writer libreoffice-calc; do
    assert_no_pkg "$pkg"
done
assert_no_pkg rhythmbox
assert_no_pkg shotwell
assert_no_pkg transmission-gtk
assert_no_pkg transmission-common

# LibreOffice must be absent from flatpak too — never installed there by us,
# but the check catches a leftover from a hand-installed override.
if command -v flatpak >/dev/null 2>&1; then
    assert_no_flatpak org.libreoffice.LibreOffice
fi

# ----- Retention (documented; never touched by script 13) --------------------
assert_pkg evolution-data-server
assert_pkg deja-dup
assert_pkg remmina
assert_pkg simple-scan

finalize
