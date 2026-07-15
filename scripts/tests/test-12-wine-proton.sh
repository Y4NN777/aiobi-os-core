#!/usr/bin/env bash
# =============================================================================
# Test — Step 12 — Wine + Proton (Windows interoperability)
# =============================================================================
# Verifies that the Wine binary is on PATH, that a Proton-GE tree has been
# installed (either under a user home compat-tools dir or via the
# /usr/local/bin/proton symlink script 12 creates), and that the system MIME
# association routes .exe / .msi / .msdownload / .msdos-program through
# wine.desktop.
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 12 — Wine + Proton-GE installed with .exe MIME routing"

assert_binary wine

# Proton-GE lives under either a user home's Steam compat-tools dir, or is
# accessible via the /usr/local/bin/proton symlink script 12 creates. We
# accept either as evidence of a successful install.
if compgen -G "/home/*/.steam/root/compatibilitytools.d/GE-Proton*" >/dev/null \
   || [ -e /usr/local/bin/proton ] \
   || [ -d /opt/proton-ge ]; then
    pass "Proton-GE tree installed"
else
    fail "Proton-GE tree installed" "no GE-Proton dir under any home, no /usr/local/bin/proton, no /opt/proton-ge"
fi

# System-wide MIME associations installed by script 12.
MIME=/etc/xdg/mimeapps.list.d/aiobi-wine.list
assert_file "$MIME"
if [ -f "$MIME" ]; then
    assert_grep "$MIME" "application/x-ms-dos-executable=wine.desktop"
    assert_grep "$MIME" "application/x-msi=wine.desktop"
fi

finalize
