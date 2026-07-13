#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 09 — GNOME Terminal profile Aïobi palette
# ----------------------------------------------------------------------------
# Purpose : detach the default gnome-terminal profile from GTK theme colors
#           and inject an Aïobi 16-color palette + brand background/cursor.
#
# Rationale
#   Without this pass, GNOME Terminal ships with Ubuntu's default aubergine
#   background (#380C2A) and Ubuntu ANSI palette; the terminal profile is a
#   separate dconf subtree and is not affected by the GTK theme injection
#   performed in step 03.
#
# Twist  : gnome-terminal lazy-creates its default profile — `dconf list
#          /org/gnome/terminal/legacy/profiles:/` returns empty until the
#          first dconf write. The UUID is resolved via `gsettings get
#          org.gnome.Terminal.ProfilesList default`, which reads the
#          ProfilesList schema initialised at first terminal launch.
#
# Idempotent: re-running overwrites the same dconf keys.
#
# Ordering: standalone. Can run any time before the user first opens the
# terminal on the shipped system. Typically run alongside the other polish
# scripts.
# ============================================================================

set -euo pipefail

# Note: this script writes to per-user dconf, so it may be run either as the
# target user (recommended) OR from root with SUDO_USER set. It handles both.

RUN_AS="${SUDO_USER:-$USER}"
if [[ "$RUN_AS" == "root" ]] && [[ -n "${SUDO_USER:-}" ]]; then
    RUN_AS="$SUDO_USER"
fi

# --- 1. Discover the default profile UUID ------------------------------------
UUID=$(su - "$RUN_AS" -c \
    "gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null" \
    | tr -d "'")

if [[ -z "$UUID" ]]; then
    echo "ERROR: could not discover default gnome-terminal profile UUID."
    echo "Cause: gnome-terminal has never been launched by user $RUN_AS,"
    echo "so the ProfilesList schema is not yet populated in per-user dconf."
    echo "Fix: launch gnome-terminal once, close, re-run this script."
    exit 3
fi

P="/org/gnome/terminal/legacy/profiles:/:${UUID}/"

# --- 2. Detach from theme colors + transparency ------------------------------
su - "$RUN_AS" -c "
dconf write '${P}use-theme-colors' 'false'
dconf write '${P}use-theme-transparency' 'false'
"

# --- 3. Aïobi core palette ---------------------------------------------------
# Primary Black bg, Primary White fg, violet cursor + highlight
su - "$RUN_AS" -c "
dconf write '${P}background-color'          \"'#0F1010'\"
dconf write '${P}foreground-color'          \"'#F8F8F9'\"
dconf write '${P}cursor-background-color'   \"'#7233CD'\"
dconf write '${P}cursor-foreground-color'   \"'#F8F8F9'\"
dconf write '${P}cursor-colors-set'         'true'
dconf write '${P}highlight-background-color' \"'#7233CD'\"
dconf write '${P}highlight-foreground-color' \"'#FFFFFF'\"
dconf write '${P}highlight-colors-set'      'true'
"

# --- 4. 16-color ANSI palette ------------------------------------------------
# Slot map:
#   0 black    1 red        2 green      3 yellow      4 BLUE→VIOLET  5 magenta→VIOLET-300  6 cyan   7 white
#   8 br-blk   9 br-red    10 br-grn    11 br-yellow  12 br-blue     13 br-magenta         14 br-cyan  15 br-white
# Slots 4 and 12 (BLUE) are hijacked to Aïobi violet, so `ls --color=auto`
# directories (default blue in dircolors) render violet. Slots 5 and 13 keep
# a lighter violet for interactive prompts using "magenta".
PALETTE="[\
'#0F1010',  '#D63A3A', '#65A030', '#D4A017', '#7233CD', '#B593E4', '#4AB6A6', '#F8F8F9', \
'#3A3A3D',  '#FF6B6B', '#95E063', '#FFCE45', '#B593E4', '#D4B8F0', '#7BEDD8', '#FFFFFF'\
]"
su - "$RUN_AS" -c "dconf write '${P}palette' \"$PALETTE\""

# --- 5. Verification ---------------------------------------------------------
echo "== Verification =="
echo "Profile UUID:         $UUID"
echo "Background:           $(su - "$RUN_AS" -c "dconf read '${P}background-color'")"
echo "Foreground:           $(su - "$RUN_AS" -c "dconf read '${P}foreground-color'")"
echo "Cursor:               $(su - "$RUN_AS" -c "dconf read '${P}cursor-background-color'")"
echo "use-theme-colors:     $(su - "$RUN_AS" -c "dconf read '${P}use-theme-colors'")"

echo "== 09-terminal-profile.sh done =="
echo "Effect: close+reopen gnome-terminal windows to see the new palette."
