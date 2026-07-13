#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 08 — Inject Aïobi gnome-shell theme
# ----------------------------------------------------------------------------
# Purpose : ship a gnome-shell theme "Aiobi" cloned from Yaru-magenta-dark with
#           the primary magenta hex #B34CB3 sed-replaced by Aïobi violet #7233CD.
#           Installed at /usr/share/themes/Aiobi/gnome-shell/, activated via the
#           user-theme extension (gnome-shell-extensions package).
#
# Rationale
#   An overlay approach that only sets user-theme.name in dconf without
#   shipping the theme itself leaves the GNOME Shell top bar (calendar
#   dropdown, Activities search, Quick Settings) falling back to the Yaru
#   default; and the `gnome-shell-extensions` metapackage that provides the
#   `user-theme` extension must be installed for the dconf key to have any
#   consumer.
#
# References
#   - Yaru upstream common/accent-colors.scss.in — magenta primary #B34CB3
#     https://github.com/ubuntu/yaru/blob/master/common/accent-colors.scss.in
#
# Idempotent: re-running restores from backup and re-applies sed cleanly.
#
# Ordering: run AFTER 01-install-extensions.sh (which installs dash-to-panel
# so user-theme can co-exist) but BEFORE 06-apply-persistence.sh (which locks
# the theme name in system dconf). Typical order: 01 → 08 → 06.
# ============================================================================

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Must run as root (sudo)."; exit 1; }

# On Ubuntu 24.04, yaru-theme-gnome-shell installs its variants under
#   /usr/share/gnome-shell/theme/Yaru-*
# rather than under /usr/share/themes/Yaru-*/gnome-shell/ as older
# releases did. The user-theme GNOME Shell extension however loads
# themes from /usr/share/themes/<Name>/gnome-shell/, so we clone from
# the actual source location and install into the extension-lookup
# location under the Aïobi name.
SRC="/usr/share/gnome-shell/theme/Yaru-magenta-dark"
DST="/usr/share/themes/Aiobi/gnome-shell"
STAGING="/tmp/aiobi-shell-src"

# --- 1. Ensure the required packages are installed --------------------------
# yaru-theme-gnome-shell ships the Yaru-magenta-dark shell theme;
# gnome-shell-extensions ships the user-theme extension that lets the
# derived theme be selected via the /org/gnome/shell/extensions/user-theme/
# dconf schema.
export DEBIAN_FRONTEND=noninteractive
apt-get install -y yaru-theme-gnome-shell gnome-shell-extensions

# --- 2. Sanity check the Yaru variant is installed --------------------------
if [[ ! -f "$SRC/gnome-shell.css" ]]; then
    echo "ERROR: $SRC/gnome-shell.css not found even after apt install."
    echo "  Expected location on Ubuntu 24.04: /usr/share/gnome-shell/theme/Yaru-magenta-dark/"
    ls -la /usr/share/gnome-shell/theme/ 2>/dev/null | head -20
    exit 2
fi

# --- 3. Enable it for the invoking user (idempotent — enable is safe if on) ---
# Only run gnome-extensions if a graphical session is live (chroot mode has no
# session — enablement then happens at first user login via dconf lock in
# 06-apply-persistence.sh).
if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] || [[ -d "/run/user/${SUDO_UID:-$EUID}/dconf" ]]; then
    # Extract user for gnome-extensions call
    RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
    su - "$RUN_USER" -c \
        "gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com" \
        2>/dev/null || echo "note: gnome-extensions enable deferred (no live session)"
fi

# --- 4. Stage a clone of the Yaru shell theme --------------------------------
rm -rf "$STAGING"
cp -r "$SRC" "$STAGING"

# --- 5. Sed the primary Yaru magenta family into Aïobi violet family ---------
# Yaru magenta primary: #B34CB3 (from Yaru accent-colors.scss.in optimize-contrast base)
# Aïobi violet primary: #7233CD
# The rgb() and rgba() forms may also appear in the compiled CSS.
sed -i \
    -e 's/#B34CB3/#7233CD/gI' \
    -e 's/rgb(179,\s*76,\s*179)/rgb(114, 51, 205)/g' \
    -e 's/rgba(179,\s*76,\s*179/rgba(114, 51, 205/g' \
    "$STAGING/gnome-shell.css"

# --- 6. Backup existing Aïobi shell theme dir (idempotent restore path) ------
if [[ -d "$DST" && ! -d "${DST}.aiobi.bak" ]]; then
    cp -r "$DST" "${DST}.aiobi.bak"
fi

# --- 7. Install --------------------------------------------------------------
mkdir -p "$(dirname "$DST")"
rm -rf "$DST"
cp -r "$STAGING" "$DST"

# --- 8. Point the user-theme dconf key at Aiobi (system-default, unlocked) ---
# Note: /etc/dconf/db/local.d/00-aiobi-branding + dconf update happens in
# 06-apply-persistence.sh. Here we only write the runtime value if a session
# exists — otherwise the persistence script does it at compile time.
if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    dconf write /org/gnome/shell/extensions/user-theme/name "'Aiobi'" \
        2>/dev/null || true
fi

# --- 9. Verification ---------------------------------------------------------
echo "== Verification =="
ls -la "$DST/gnome-shell.css"
echo "  magenta remnants in Aïobi shell CSS:  $(grep -c '#B34CB3' "$DST/gnome-shell.css" || echo 0)"
echo "  Aïobi violet in Aïobi shell CSS:      $(grep -c '#7233CD' "$DST/gnome-shell.css" || echo 0)"

# Cleanup staging (backup at ${DST}.aiobi.bak is preserved)
rm -rf "$STAGING"

echo "== 08-inject-shell-theme.sh done =="
echo "Requires GNOME session logout+login to take effect on the running system."
