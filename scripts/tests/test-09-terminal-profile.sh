#!/usr/bin/env bash
# =============================================================================
# Test — Step 09 — GNOME Terminal profile (Aïobi palette)
# =============================================================================
# Verifies that the Aïobi terminal keyfile is installed at
# /etc/dconf/db/local.d/30-aiobi-terminal, that it carries the brand
# background (#0F1010) and foreground (#F8F8F9), and that a palette line
# is defined so the 16-colour ANSI mapping is customised (not left to
# defaults).
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 09 — GNOME Terminal Aïobi palette keyfile"

KEYFILE="/etc/dconf/db/local.d/30-aiobi-terminal"

assert_file "$KEYFILE"

if [ -f "$KEYFILE" ]; then
    # Brand-critical colours.
    assert_grep "$KEYFILE" "#0F1010"
    assert_grep "$KEYFILE" "#F8F8F9"

    # Palette line must exist — otherwise the 16-colour ANSI mapping
    # falls back to the vendor default and defeats the rebrand.
    if grep -qE "^palette=" "$KEYFILE"; then
        pass "$KEYFILE defines a palette line"
    else
        fail "$KEYFILE defines a palette line" "no palette= entry"
    fi
fi

finalize
