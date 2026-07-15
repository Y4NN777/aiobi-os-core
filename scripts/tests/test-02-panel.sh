#!/usr/bin/env bash
# =============================================================================
# Test — Step 02 — Panel configuration
# =============================================================================
# Verifies that the dash-to-panel system dconf keyfile is installed and
# compiled into the local dconf database with the expected Aïobi defaults
# (bottom position, 64 px, brand-black background).
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 02 — dash-to-panel dconf keyfile compiled"

PANEL_KEYFILE="/etc/dconf/db/local.d/20-aiobi-panel"
COMPILED_DB="/etc/dconf/db/local"

assert_file "$PANEL_KEYFILE"
assert_file "$COMPILED_DB"

# Content sanity — brand-critical values must be in the keyfile.
if [ -f "$PANEL_KEYFILE" ]; then
    assert_grep "$PANEL_KEYFILE" "BOTTOM"
    assert_grep "$PANEL_KEYFILE" "64"
    assert_grep "$PANEL_KEYFILE" "0F1010"
fi

finalize
