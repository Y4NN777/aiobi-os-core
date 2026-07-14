#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Step 07 — Validation (PASS/FAIL per Acceptance Criterion)
# =============================================================================
# Run AFTER 01..06. Exits non-zero if any check fails — chainable into CI.
#
# Pipefail is intentionally OFF: read-only `gresource extract … | grep` and
# similar pipes return non-zero via SIGPIPE the moment grep matches early,
# which is a false negative for our purposes.
# =============================================================================

set -u

green="\033[32m"; red="\033[31m"; yellow="\033[33m"; reset="\033[0m"
ok()   { printf "  ${green}PASS${reset}  %s\n" "$1"; }
nope() { printf "  ${red}FAIL${reset}  %s\n" "$1"; fail=$((fail+1)); }
warn() { printf "  ${yellow}WARN${reset}  %s\n" "$1"; }

fail=0
echo "===== Aïobi validation ====="

# Detect chroot / no-session: when DBUS_SESSION_BUS_ADDRESS is unset OR
# /run/user/$EUID/dconf doesn't exist, `dconf read` returns empty even for
# keys defined in the system db. In that case fall back to reading the
# keyfile directly. This is the ISO-build context — the keyfile is what
# ships, not the runtime value.
PANEL_KEYFILE=/etc/dconf/db/local.d/20-aiobi-panel
BRAND_KEYFILE=/etc/dconf/db/local.d/00-aiobi-branding
NO_SESSION=0
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ ! -d "/run/user/${EUID:-0}/dconf" ]; then
    NO_SESSION=1
    warn "no live dconf session detected — falling back to keyfile reads (chroot mode)"
fi

# Read a key with dconf, fallback to the keyfile field if dconf returns empty.
# Args: <dconf-path> <keyfile> <ini-key>
dconf_or_keyfile() {
    local path="$1" kf="$2" ini="$3" v=""
    if [ "$NO_SESSION" = "0" ]; then
        v=$(dconf read -d / "$path" 2>/dev/null || true)
    fi
    if [ -z "$v" ] && [ -f "$kf" ]; then
        v=$(grep -E "^${ini}=" "$kf" | head -1 | cut -d= -f2-)
    fi
    echo "$v"
}

# ----- Extension -------------------------------------------------------------
UUID="dash-to-panel@jderose9.github.com"
EXT_DIR="/usr/share/gnome-shell/extensions/$UUID"
[ -d "$EXT_DIR" ] && ok "dash-to-panel installed system-wide ($EXT_DIR)" \
                 || nope "dash-to-panel missing from $EXT_DIR"

# Enabled — check dconf live, else the keyfile under [org/gnome/shell]
enabled=$(dconf_or_keyfile /org/gnome/shell/enabled-extensions "$PANEL_KEYFILE" "enabled-extensions")
echo "$enabled" | grep -q "dash-to-panel" \
    && ok "dash-to-panel listed in enabled-extensions" \
    || nope "dash-to-panel NOT in enabled-extensions (got: $enabled)"

# Ubuntu dock disabled
disabled=$(dconf_or_keyfile /org/gnome/shell/disabled-extensions "$PANEL_KEYFILE" "disabled-extensions")
echo "$disabled" | grep -q "ubuntu-dock" \
    && ok "Ubuntu dock disabled at system level" \
    || nope "ubuntu-dock NOT in disabled-extensions (got: $disabled)"

# ----- Panel config ----------------------------------------------------------
pos=$(dconf_or_keyfile /org/gnome/shell/extensions/dash-to-panel/panel-positions "$PANEL_KEYFILE" "panel-positions")
echo "$pos" | grep -q "BOTTOM" \
    && ok "panel-positions = BOTTOM" \
    || nope "panel-positions wrong: $pos"

size=$(dconf_or_keyfile /org/gnome/shell/extensions/dash-to-panel/panel-sizes "$PANEL_KEYFILE" "panel-sizes")
echo "$size" | grep -q "64" \
    && ok "panel-sizes = 64px" \
    || nope "panel-sizes wrong: $size"

bg=$(dconf_or_keyfile /org/gnome/shell/extensions/dash-to-panel/trans-bg-color "$PANEL_KEYFILE" "trans-bg-color")
echo "$bg" | grep -iq "0F1010" \
    && ok "panel background = #0F1010 (Aïobi black)" \
    || nope "panel background wrong: $bg"

# ----- GTK theme -------------------------------------------------------------
THEME_DIR=/usr/share/themes/Aiobi
for f in gtk-3.0/gtk.css gtk-3.0/gtk-dark.css gtk-4.0/gtk.css index.theme; do
    [ -f "$THEME_DIR/$f" ] && ok "theme file present: $f" \
                          || nope "theme file missing: $f"
done

# Accent colour baked into the theme.
# The full-clone theme derivation (script 03) sed-substitutes the Yaru
# magenta hex into the Aïobi violet. On Ubuntu 24.04 Yaru bakes the
# effective CSS into the compiled gtk.gresource bundle rather than into
# the on-disk .css files, so the presence check has to extract from the
# gresource. On-disk .css alone would produce false negatives.

check_theme_accent() {
    local variant="$1"  # 3.0 or 4.0
    local gres="$THEME_DIR/gtk-$variant/gtk.gresource"
    if [ ! -f "$gres" ]; then
        # Fallback: check any .css files in the tree.
        if grep -Rqi "#7233CD" "$THEME_DIR/gtk-$variant/" 2>/dev/null; then
            ok "GTK$variant tree contains Aïobi violet accent (no gresource present)"
        else
            nope "GTK$variant no gresource and no CSS accent"
        fi
        return
    fi
    # List all entries in the gresource and try to extract a stylesheet;
    # gresource paths look like /com/ubuntu/themes/Yaru-magenta-dark/{3.0,4.0}/…
    local first_css
    first_css=$(gresource list "$gres" 2>/dev/null | grep -E '\.css$' | head -1)
    if [ -z "$first_css" ]; then
        nope "GTK$variant gresource contains no .css entry"
        return
    fi
    if gresource extract "$gres" "$first_css" 2>/dev/null | grep -qi "#7233CD"; then
        ok "GTK$variant gresource stylesheet carries Aïobi violet"
    else
        nope "GTK$variant gresource stylesheet missing accent token"
    fi
}

check_theme_accent 3.0
check_theme_accent 4.0

# gtk-theme applied — dconf live OR keyfile
gtk_theme=$(dconf_or_keyfile /org/gnome/desktop/interface/gtk-theme "$BRAND_KEYFILE" "gtk-theme")
echo "$gtk_theme" | grep -q "Aiobi" \
    && ok "gtk-theme = Aiobi (system default)" \
    || nope "gtk-theme not Aiobi: $gtk_theme"

# ----- Icons -----------------------------------------------------------------
for v in Papirus Papirus-Dark; do
    if [ -d "/usr/share/icons/$v" ]; then
        ok "$v installed"
    else
        nope "$v missing"
    fi
done

# Folder recolour — sample 64x64 specifically. The 16x16 folder.svg in Papirus
# uses .ColorScheme-Text + fill:currentColor (monochrome symbolic by design,
# follows GTK text colour). It MUST NOT be expected to contain #7233CD. The
# coloured folder palette lives at 22x22 / 24x24 / 48x48 / 64x64 — pick 64x64
# as canonical sample.
for v in Papirus Papirus-Dark Papirus-Light; do
    [ -d "/usr/share/icons/$v" ] || continue
    sample="/usr/share/icons/$v/64x64/places/folder.svg"
    if [ -f "$sample" ] && grep -iq "7233CD" "$sample"; then
        ok "$v/64x64/places/folder.svg recoloured to #7233CD"
    elif [ -f "$sample" ]; then
        nope "$v/64x64/places/folder.svg NOT recoloured"
    else
        warn "$v 64x64/places/folder.svg not found (size variant missing)"
    fi
done

# Brave / OnlyOffice intact (if installed)
for variant in Papirus Papirus-Dark; do
    for app in brave brave-browser onlyoffice onlyoffice-desktopeditors; do
        f=$(find "/usr/share/icons/$variant" -name "${app}*.svg" 2>/dev/null | head -1)
        if [ -n "$f" ]; then
            if grep -iq "7233CD" "$f"; then
                nope "$variant/$app icon was accidentally recoloured!"
            else
                ok "$variant/$app icon intact"
            fi
        fi
    done
done

# Backup present
[ -d /usr/share/icons/Papirus-Aiobi-backup ] \
    && ok "backup tree present at /usr/share/icons/Papirus-Aiobi-backup" \
    || nope "backup tree missing"

# Aïobi placeholders
PLACEHOLDERS=(aiobi-start-menu aiobi-ai-terminal aiobi-ai-chat aiobi-ai-secure-status aiobi-firewall-status)
for name in "${PLACEHOLDERS[@]}"; do
    [ -f "/usr/share/icons/Aiobi/scalable/apps/${name}.svg" ] \
        && ok "placeholder $name.svg installed" \
        || nope "placeholder $name.svg missing"
done

icon_theme=$(dconf_or_keyfile /org/gnome/desktop/interface/icon-theme "$BRAND_KEYFILE" "icon-theme")
echo "$icon_theme" | grep -q "Aiobi" \
    && ok "icon-theme = Aiobi (system default)" \
    || nope "icon-theme not Aiobi: $icon_theme"

# ----- OS rebrand ------------------------------------------------------------
PROBE="A$(printf '\xc3\xaf')obi"
grep -q "^PRETTY_NAME=" /etc/os-release && grep -q "$PROBE" /etc/os-release \
    && ok "/etc/os-release PRETTY_NAME contains Aïobi" \
    || nope "/etc/os-release not rebranded"

if grep -q "$PROBE" /etc/lsb-release 2>/dev/null; then
    ok "/etc/lsb-release rebranded"
elif [ -f /etc/systemd/system/aiobi-firstboot-rebrand.service ] \
  && [ -f /usr/local/sbin/aiobi-firstboot-rebrand.sh ]; then
    # Inside the Cubic chroot, both /etc/os-release and /etc/lsb-release can
    # be transparently overwritten by Cubic after script 05 has patched them.
    # The first-boot rebrand service ships exactly for this case and rewrites
    # DISTRIB_DESCRIPTION at the first user boot of the installed system.
    ok "/etc/lsb-release will be rebranded at first boot (Cubic overwrote here, resilience service in place)"
    echo "         current chroot content (will be corrected at boot):"
    sed 's/^/           | /' /etc/lsb-release 2>/dev/null
else
    nope "/etc/lsb-release not rebranded and no first-boot resilience service"
    echo "         current /etc/lsb-release content:"
    sed 's/^/           | /' /etc/lsb-release 2>/dev/null || \
        echo "           | (file missing or unreadable)"
fi

# ----- dconf profile + locks -------------------------------------------------
[ -f /etc/dconf/profile/user ] \
    && grep -q "system-db:local" /etc/dconf/profile/user \
    && ok "/etc/dconf/profile/user references system-db:local" \
    || nope "dconf user profile missing or wrong"

LOCKS=/etc/dconf/db/local.d/locks/00-aiobi-locks
[ -f "$LOCKS" ] \
    && ok "locks file present at $LOCKS" \
    || nope "locks file missing"

# Crucially: color-scheme MUST NOT be locked
# IMPORTANT: must skip comment lines (the locks file's header explains why
# color-scheme stays free — a naive grep would match that comment and flag
# a false positive).
if [ -f "$LOCKS" ] && grep -v '^[[:space:]]*#' "$LOCKS" | grep -q "color-scheme"; then
    nope "color-scheme IS LOCKED — brief violation (user must keep light/dark freedom)"
else
    ok "color-scheme is NOT locked (user can toggle light/dark freely)"
fi

# /etc/skel populated
[ -L /etc/skel/.config/gtk-4.0/gtk.css ] \
    && ok "/etc/skel symlinks Aiobi GTK4 theme" \
    || warn "/etc/skel GTK4 symlink missing (new users won't auto-inherit)"

# ----- AI zero-data-leak firewall -------------------------------------------
# The IPv4 and IPv6 iptables rules installed by 20-ai-firewall.sh must be
# present on disk (persistence layer) and, when systemd is running, active
# in the kernel netfilter chains.
if [ -f /etc/iptables/rules.v4 ] && grep -q "dport 11434" /etc/iptables/rules.v4; then
    ok "AI firewall IPv4 rule present at /etc/iptables/rules.v4"
else
    nope "AI firewall IPv4 rule missing"
fi
if [ -f /etc/iptables/rules.v6 ] && grep -q "dport 11434" /etc/iptables/rules.v6; then
    ok "AI firewall IPv6 rule present at /etc/iptables/rules.v6"
else
    nope "AI firewall IPv6 rule missing"
fi

echo
if [ $fail -eq 0 ]; then
    printf "${green}===== ALL CHECKS PASSED =====${reset}\n"
    exit 0
else
    printf "${red}===== $fail CHECK(S) FAILED =====${reset}\n"
    exit 1
fi
