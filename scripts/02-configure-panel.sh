#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Step 02 — Configure dash-to-panel via system dconf
# =============================================================================
# WHAT
#   Copies config/aiobi-panel.dconf into /etc/dconf/db/local.d/20-aiobi-panel
#   and runs `dconf update` to compile the binary db so the panel reads
#   Aïobi defaults at every login.
#
# WHY here and not at user level
#   `gsettings set` writes to ~/.config/dconf/user, a per-user binary. For an
#   OS ship target every user must inherit the panel layout — that's only
#   achievable through /etc/dconf/db/local.d/ (system db, layered under the
#   user db by /etc/dconf/profile/user).
#
# SOURCES
#   - https://help.gnome.org/admin/system-admin-guide/stable/dconf-keyfiles.html
#   - https://github.com/home-sweet-gnome/dash-to-panel/blob/master/schemas/org.gnome.shell.extensions.dash-to-panel.gschema.xml
#
# IDEMPOTENT: overwrites the keyfile on every run, then recompiles.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/config/aiobi-panel.dconf"
DEST_DIR="/etc/dconf/db/local.d"
DEST="$DEST_DIR/20-aiobi-panel"
PROFILE_SRC="$HERE/config/dconf-profile"
PROFILE_DEST="/etc/dconf/profile/user"

echo "==> Aïobi — 02-configure-panel.sh"

[ -f "$SRC" ] || { echo "ERROR: $SRC missing — checkout incomplete"; exit 1; }

# Ensure the dconf user profile exists (idempotent — script 06 does the same;
# we duplicate here so 02 works in isolation during QA).
mkdir -p "$(dirname "$PROFILE_DEST")"
install -m 0644 "$PROFILE_SRC" "$PROFILE_DEST"
echo "  installed $PROFILE_DEST"

# Install the panel keyfile
mkdir -p "$DEST_DIR"
install -m 0644 "$SRC" "$DEST"
echo "  installed $DEST"

# Recompile system dconf db
dconf update
echo "  dconf db recompiled"

# Quick readback so the user can confirm the keys took effect
echo
echo "  Readback (system defaults — visible only after first user login on Wayland):"
for k in panel-positions panel-sizes trans-bg-color intellihide; do
    v=$(dconf read -d / "/org/gnome/shell/extensions/dash-to-panel/$k" 2>/dev/null || true)
    printf "    %-20s = %s\n" "$k" "${v:-(unset)}"
done

echo "==> 02 done"
