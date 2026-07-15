#!/usr/bin/env bash
# =============================================================================
# Test — Step 06 — System-wide persistence (dconf + skel)
# =============================================================================
# Verifies that the dconf user profile points at the local system db, that
# the local db is compiled, that the locks file is present WITHOUT locking
# color-scheme (brand rule — users must keep light/dark freedom), that
# /etc/skel carries the Aïobi GTK4 symlink, and that the two brand fonts
# expected by the system dconf defaults are installed.
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 06 — dconf profile, locks and skel populated"

# 1. Profile chain — system-db:local must be layered under user-db:user.
assert_file /etc/dconf/profile/user
if [ -f /etc/dconf/profile/user ]; then
    assert_grep /etc/dconf/profile/user "system-db:local"
    assert_grep /etc/dconf/profile/user "user-db:user"
fi

# 2. Compiled dconf db.
assert_file /etc/dconf/db/local

# 3. Branding keyfile + locks file.
assert_file /etc/dconf/db/local.d/00-aiobi-branding
LOCKS=/etc/dconf/db/local.d/locks/00-aiobi-locks
assert_file "$LOCKS"

# color-scheme MUST NOT be locked (comment lines excluded from the check).
if [ -f "$LOCKS" ]; then
    if grep -v '^[[:space:]]*#' "$LOCKS" | grep -q "color-scheme"; then
        fail "color-scheme is NOT locked" "found /org/gnome/desktop/interface/color-scheme in $LOCKS"
    else
        pass "color-scheme is NOT locked"
    fi
fi

# 4. /etc/skel carries the Aïobi GTK4 symlink so new users inherit the theme.
if [ -L /etc/skel/.config/gtk-4.0/gtk.css ]; then
    pass "/etc/skel/.config/gtk-4.0/gtk.css is a symlink"
else
    fail "/etc/skel/.config/gtk-4.0/gtk.css is a symlink" "not a symlink or missing"
fi

# 5. .bashrc template exists in skel (baseline shell config for new users).
assert_file /etc/skel/.bashrc

# 6. Brand fonts declared by 00-aiobi-branding must be installed.
assert_pkg fonts-inter
assert_pkg fonts-jetbrains-mono

finalize
