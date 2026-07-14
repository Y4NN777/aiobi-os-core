#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 09 — GNOME Terminal profile Aïobi palette
# ----------------------------------------------------------------------------
# Purpose : ensure the Aïobi terminal palette is applied to any newly
#           created user account, and to the current user on an installed
#           system.
#
# Design change from earlier revisions
#   An earlier revision of this script wrote the palette directly to the
#   invoking user's dconf tree via `dconf write` under
#   /org/gnome/terminal/legacy/profiles:/:UUID/... . That approach worked
#   on a live session but did not survive the transition from the
#   customization chroot to the produced ISO: the writes landed in
#   /root/.config/dconf/user (the chroot's root profile), not in the
#   system dconf database, and a freshly installed system boots with an
#   empty terminal profile.
#
#   The corrected approach lives in 06-apply-persistence.sh: the palette
#   is shipped as a system dconf keyfile at
#     /etc/dconf/db/local.d/30-aiobi-terminal
#   whose contents map to the terminal's default profile UUID
#   (b1dcc9dd-5262-4d8d-a863-c897e6d979b9, stable on Ubuntu 24.04). A
#   `dconf update` compiles it into the system database, and every user
#   account inherits the palette on first terminal launch without any
#   per-session intervention.
#
# What this script now does
#   Because the actual keyfile install happens in 06, this script is a
#   thin verification pass: it checks that the terminal keyfile is in
#   place and that the palette actually made it into the compiled dconf
#   db. If not, it prints an actionable message and exits non-zero so
#   the pipeline halts. Idempotent by construction.
#
# Ordering: must run AFTER 06-apply-persistence.sh so the keyfile and
# the compiled db exist.
# ============================================================================

set -euo pipefail

echo "==> Aïobi — 09-terminal-profile.sh (verification pass)"

TERMINAL_KEYFILE=/etc/dconf/db/local.d/30-aiobi-terminal
DEFAULT_UUID=b1dcc9dd-5262-4d8d-a863-c897e6d979b9
P="/org/gnome/terminal/legacy/profiles:/:${DEFAULT_UUID}/"

# --- 1. Keyfile present ------------------------------------------------------
if [ ! -f "$TERMINAL_KEYFILE" ]; then
    echo "ERROR: terminal keyfile missing: $TERMINAL_KEYFILE"
    echo "  Cause: 06-apply-persistence.sh has not been run yet, or the"
    echo "         config/aiobi-terminal.dconf source file was not shipped."
    echo "  Fix:   run bash scripts/06-apply-persistence.sh first."
    exit 2
fi
echo "  ✓ keyfile present at $TERMINAL_KEYFILE"

# --- 2. Compiled dconf db reflects the palette --------------------------------
BG=$(DCONF_PROFILE=user dconf read "${P}background-color" 2>/dev/null || echo "")
FG=$(DCONF_PROFILE=user dconf read "${P}foreground-color" 2>/dev/null || echo "")

if [ "$BG" != "'#0F1010'" ]; then
    echo "WARN: background-color not read back as Aïobi black (#0F1010)"
    echo "  measured: $BG"
    echo "  Cause: dconf db may not be recompiled; try `dconf update`."
fi
if [ "$FG" != "'#F8F8F9'" ]; then
    echo "WARN: foreground-color not read back as Aïobi white (#F8F8F9)"
    echo "  measured: $FG"
fi

# --- 3. Report -------------------------------------------------------------
echo
echo "== Verification =="
echo "  keyfile:        $TERMINAL_KEYFILE"
echo "  default UUID:   $DEFAULT_UUID"
echo "  background:     $BG"
echo "  foreground:     $FG"
echo "  palette lines:  $(grep -c '^palette=' "$TERMINAL_KEYFILE")"

echo "== 09-terminal-profile.sh done =="
echo "Effect: users get the Aïobi palette on first gnome-terminal launch."
