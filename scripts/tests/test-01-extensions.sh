#!/usr/bin/env bash
# =============================================================================
# Test — Step 01 — GNOME extensions
# =============================================================================
# Verifies that scripts/01-install-extensions.sh has installed dash-to-panel
# system-wide, that the system dconf keyfile enables it, that Ubuntu's own
# dock is disabled, and that the extensions install directory exists.
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 01 — dash-to-panel installed, ubuntu-dock disabled"

UUID="dash-to-panel@jderose9.github.com"
EXT_ROOT="/usr/share/gnome-shell/extensions"
EXT_DIR="$EXT_ROOT/$UUID"
PANEL_KEYFILE="/etc/dconf/db/local.d/20-aiobi-panel"

# Extensions install directory must exist and be populated.
assert_dir "$EXT_ROOT"
assert_dir "$EXT_DIR"
assert_file "$EXT_DIR/metadata.json"

# dash-to-panel enabled + ubuntu-dock disabled via the system-wide keyfile
# (chroot-safe read — we do NOT go through the runtime dconf DB).
if [ -f "$PANEL_KEYFILE" ]; then
    assert_grep "$PANEL_KEYFILE" "dash-to-panel"
    assert_grep "$PANEL_KEYFILE" "ubuntu-dock"
else
    fail "panel keyfile: $PANEL_KEYFILE" "missing — extension enablement cannot be verified"
fi

finalize
