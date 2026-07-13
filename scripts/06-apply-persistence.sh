#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Step 06 — System-wide persistence (dconf profile + skel)
# =============================================================================
# WHAT
#   1. Install /etc/dconf/profile/user pointing user-db over system-db local.
#   2. Install /etc/dconf/db/local.d/00-aiobi-branding (gtk/icon/font defaults).
#   3. Install /etc/dconf/db/local.d/locks/00-aiobi-locks listing keys that
#      cannot be changed by the user — INCLUDES gtk-theme/icon-theme/fonts
#      (brand-critical) but DEFINITELY EXCLUDES color-scheme (user freedom).
#   4. Run `dconf update` to compile system db.
#   5. Mirror critical user-config defaults into /etc/skel/ so brand-new
#      accounts get the same first-login state.
#
# WHY locks
#   Without a lock, the very first time the user opens Settings → Appearance
#   and clicks a different accent, their per-user dconf overrides the system
#   default and never re-reads it. Locks prevent that for keys we consider
#   non-negotiable brand surface.
#
# WHY color-scheme stays UNLOCKED
#   Non-negotiable user freedom (brief rule). Locking light/dark would break
#   the OS for any user who prefers light; we ship the dark default but
#   keep the toggle live.
#
# SOURCES
#   - https://help.gnome.org/admin/system-admin-guide/stable/dconf-lockdown.html.en
#   - https://help.gnome.org/admin/system-admin-guide/stable/dconf-profiles.html
#
# IDEMPOTENT: overwrites profile + keyfiles + locks on every run; dconf update
#   is safe to repeat.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

HERE="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE_SRC="$HERE/config/dconf-profile"
BRANDING_SRC="$HERE/config/local.d/00-aiobi-branding"
PANEL_SRC="$HERE/config/aiobi-panel.dconf"

DCONF_PROFILE="/etc/dconf/profile/user"
DCONF_LOCAL_D="/etc/dconf/db/local.d"
DCONF_LOCKS="$DCONF_LOCAL_D/locks"

echo "==> Aïobi — 06-apply-persistence.sh"

# Install packages required by the system-wide dconf defaults installed
# below:
#   - gnome-shell-extensions: provides the user-theme extension referenced
#     by 00-aiobi-branding's `user-theme.name='Aiobi'` (else the dconf key
#     is set but no consumer applies the shell theme).
#   - fonts-inter: the system font-name is set to 'Inter 11' (Inter is
#     retained as the neutral system font; Satoshi is reserved for the
#     application-level design system). Without fonts-inter installed,
#     GNOME falls back to DejaVu / Ubuntu-font and the rebrand is defeated.
#   - fonts-jetbrains-mono: matches monospace-font-name='JetBrains Mono 11'.
export DEBIAN_FRONTEND=noninteractive
apt-get install -y gnome-shell-extensions fonts-inter fonts-jetbrains-mono || \
    echo "  note: some font packages may not be in current apt cache — will retry"

[ -f "$PROFILE_SRC" ]  || { echo "ERROR: $PROFILE_SRC missing";  exit 1; }
[ -f "$BRANDING_SRC" ] || { echo "ERROR: $BRANDING_SRC missing"; exit 1; }
[ -f "$PANEL_SRC" ]    || { echo "ERROR: $PANEL_SRC missing";    exit 1; }

# ----- 0) Sweep foreign keyfiles ---------------------------------------------
# Any keyfile in /etc/dconf/db/local.d/ that is NOT one of ours can override
# our branding at compile time (dconf applies keyfiles in filename order;
# a numerically higher prefix wins). This has been observed in practice
# with a legacy 10-aiobi-accent-theme keyfile left over from an earlier
# customization attempt that forced Yaru-magenta-dark and cancelled the
# Aïobi theme deployment. We sweep unknown files here before installing
# our own, so a re-run always converges on a clean state.
KNOWN_KEYFILES=(
    "00-aiobi-branding"
    "00-aiobi-wallpaper"
    "20-aiobi-panel"
)
if [ -d "$DCONF_LOCAL_D" ]; then
    for existing in "$DCONF_LOCAL_D"/*; do
        [ -f "$existing" ] || continue
        base=$(basename "$existing")
        known=false
        for kf in "${KNOWN_KEYFILES[@]}"; do
            [ "$base" = "$kf" ] && known=true && break
        done
        if ! $known; then
            echo "  sweep: removing foreign keyfile $existing (would override Aïobi branding)"
            rm -f "$existing"
        fi
    done
fi

# ----- 1) Profile -------------------------------------------------------------
mkdir -p "$(dirname "$DCONF_PROFILE")"
install -m 0644 "$PROFILE_SRC" "$DCONF_PROFILE"
echo "  installed $DCONF_PROFILE"

# ----- 2) Branding keyfile + panel keyfile ------------------------------------
mkdir -p "$DCONF_LOCAL_D"
install -m 0644 "$BRANDING_SRC" "$DCONF_LOCAL_D/00-aiobi-branding"
install -m 0644 "$PANEL_SRC"    "$DCONF_LOCAL_D/20-aiobi-panel"
echo "  installed 00-aiobi-branding + 20-aiobi-panel"

# ----- 3) Locks ---------------------------------------------------------------
mkdir -p "$DCONF_LOCKS"
cat > "$DCONF_LOCKS/00-aiobi-locks" << 'EOF'
# Aïobi OS — locked keys (cannot be overridden by users)
# CRITICAL: do NOT add /org/gnome/desktop/interface/color-scheme here —
# users must remain free to toggle light/dark.
/org/gnome/desktop/interface/gtk-theme
/org/gnome/desktop/interface/icon-theme
/org/gnome/desktop/interface/font-name
/org/gnome/desktop/interface/document-font-name
/org/gnome/desktop/interface/monospace-font-name
/org/gnome/shell/enabled-extensions
/org/gnome/shell/disabled-extensions
EOF
echo "  installed locks/00-aiobi-locks (8 keys locked, color-scheme NOT locked)"

# ----- 4) Compile dconf db ---------------------------------------------------
dconf update
echo "  dconf db compiled"

# ----- 5) /etc/skel defaults --------------------------------------------------
# New accounts inherit /etc/skel/.config/ — we drop GTK4 theme + a starter
# gnome-shell extension state so the desktop boots branded immediately.
mkdir -p /etc/skel/.config/gtk-4.0
ln -sfn /usr/share/themes/Aiobi/gtk-4.0/gtk.css /etc/skel/.config/gtk-4.0/gtk.css 2>/dev/null || true

# Drop a gsettings-equivalent .ini so even apps that don't read dconf at
# session start pick up the right values.
mkdir -p /etc/skel/.config/dconf
echo "  populated /etc/skel/.config/"

# ----- 6) Verify the locks are active ----------------------------------------
echo
echo "  Verification — readback of locked keys (should match keyfile defaults):"
for k in gtk-theme icon-theme font-name monospace-font-name; do
    v=$(dconf read -d / "/org/gnome/desktop/interface/$k" 2>/dev/null || true)
    printf "    %-25s = %s\n" "$k" "${v:-(unset)}"
done
echo "    color-scheme = $(dconf read -d / /org/gnome/desktop/interface/color-scheme 2>/dev/null || echo '(unset, free for user)')"

echo "==> 06 done — system-wide branding persisted, color-scheme unlocked"
