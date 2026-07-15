#!/usr/bin/env bash
# =============================================================================
# Test — Step 08 — GNOME Shell theme (Aïobi violet)
# =============================================================================
# Verifies that the Aïobi GNOME Shell theme is installed under the
# extension-lookup location and that the Aïobi violet accent has been
# sed-substituted into the shell CSS. Also confirms that the user-theme
# extension package is present so a session can consume the theme.
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 08 — GNOME Shell theme installed at user-theme lookup path"

SHELL_DIR="/usr/share/themes/Aiobi/gnome-shell"
SHELL_CSS="$SHELL_DIR/gnome-shell.css"

assert_dir "$SHELL_DIR"
assert_file "$SHELL_CSS"

# Package that ships the user-theme extension.
assert_pkg gnome-shell-extensions

# Aïobi violet must be baked into the shell CSS; Yaru magenta must be gone.
if [ -f "$SHELL_CSS" ]; then
    if grep -qi "#7233CD" "$SHELL_CSS"; then
        pass "gnome-shell.css contains Aïobi violet #7233CD"
    else
        fail "gnome-shell.css contains Aïobi violet #7233CD" "not found"
    fi
    if grep -qi "#B34CB3" "$SHELL_CSS"; then
        fail "gnome-shell.css purged of Yaru magenta #B34CB3" "still present"
    else
        pass "gnome-shell.css purged of Yaru magenta #B34CB3"
    fi
fi

finalize
