#!/usr/bin/env bash
# =============================================================================
# Test — Step 03 — GTK theme (Aïobi violet)
# =============================================================================
# Verifies that the Aïobi GTK theme tree exists under /usr/share/themes/Aiobi,
# that gtk-3.0 and gtk-4.0 subtrees are populated, that the compiled
# gresource bundle is present, and that the Aïobi violet accent (#7233CD)
# is baked into either the on-disk CSS or the compiled gresource.
# The Yaru magenta base hex (#B34CB3) must NOT remain in any on-disk CSS
# after the sed patch.
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 03 — Aïobi GTK theme installed, violet accent baked in"

THEME_DIR="/usr/share/themes/Aiobi"

assert_dir "$THEME_DIR"
assert_dir "$THEME_DIR/gtk-3.0"
assert_dir "$THEME_DIR/gtk-4.0"
assert_file "$THEME_DIR/index.theme"

# gresource bundles must be present for both GTK generations.
assert_file "$THEME_DIR/gtk-3.0/gtk.gresource"
assert_file "$THEME_DIR/gtk-4.0/gtk.gresource"

# index.theme carries the Aïobi name.
if [ -f "$THEME_DIR/index.theme" ]; then
    if grep -qE '^Name=Aiobi' "$THEME_DIR/index.theme"; then
        pass "index.theme Name=Aiobi"
    else
        fail "index.theme Name=Aiobi" "Name field not set to Aiobi"
    fi
fi

# Violet accent must be baked in — accept either on-disk CSS or gresource.
violet_seen=0
if grep -Rqi "#7233CD" "$THEME_DIR/gtk-3.0" 2>/dev/null; then
    violet_seen=1
fi
if [ "$violet_seen" = "0" ] && command -v gresource >/dev/null 2>&1; then
    for g in "$THEME_DIR/gtk-3.0/gtk.gresource" "$THEME_DIR/gtk-4.0/gtk.gresource"; do
        [ -f "$g" ] || continue
        css_entry=$(gresource list "$g" 2>/dev/null | grep -E '\.css$' | head -1)
        if [ -n "$css_entry" ] \
           && gresource extract "$g" "$css_entry" 2>/dev/null | grep -qi "#7233CD"; then
            violet_seen=1
            break
        fi
    done
fi
if [ "$violet_seen" = "1" ]; then
    pass "Aïobi violet #7233CD present in theme"
else
    fail "Aïobi violet #7233CD present in theme" "not found in CSS or gresource"
fi

# Sed patch must have removed the Yaru magenta base hex from on-disk CSS.
if grep -Rqi "#B34CB3" "$THEME_DIR/gtk-3.0" "$THEME_DIR/gtk-4.0" 2>/dev/null; then
    fail "Yaru magenta #B34CB3 removed from on-disk CSS" "still present"
else
    pass "Yaru magenta #B34CB3 removed from on-disk CSS"
fi

finalize
