#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Step 22 — Taskbar pins + desktop icons defaults
# =============================================================================
# Purpose : deliver a Windows-familiar first-boot experience on Aïobi OS.
#   (a) install Desktop Icons NG (Ding) extension so /home/<user>/Desktop
#       shortcuts and files appear on the wallpaper (GNOME 3.28+ removed
#       Nautilus-desktop; Ding is the maintained replacement);
#   (b) enable Ding + dash-to-panel + user-theme + Ubuntu appindicators as
#       the Aïobi baseline set of extensions;
#   (c) preseed org.gnome.shell.favorite-apps with the Aïobi curated app
#       row that dash-to-panel displays in the taskbar;
#   (d) preseed org.gnome.shell.extensions.ding config (show Home + Trash,
#       standard icon size, top-left start corner);
#   (e) ship default .desktop shortcuts in /etc/skel/Desktop/ so every
#       new user account created by Subiquity opens with the Aïobi
#       taskbar pins mirrored as desktop icons.
#
# The dconf keyfile lands under /etc/dconf/db/local.d/ and is compiled
# into the system db by script 06 (persistence) which runs AFTER this
# script in the orchestrator.
#
# Idempotent: apt install skips if already latest; keyfile is overwritten
# every run; /etc/skel/Desktop/ copies are `cp -f` overwrites.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi — 22-taskbar-desktop-defaults.sh"

# ----- 1) Install Ding (Desktop Icons NG) ------------------------------------
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    gnome-shell-extension-desktop-icons-ng
echo "  [apt] gnome-shell-extension-desktop-icons-ng installed"

# ----- 2) Preseed dconf keyfile ----------------------------------------------
# Extensions enabled at first login for every new user:
#   dash-to-panel   — Aïobi bottom taskbar (script 01)
#   user-theme      — allows the Aïobi gnome-shell theme (script 08)
#   ding            — desktop icons on the wallpaper (this script)
#   ubuntu-appindicators — legacy systray for AnythingLLM Electron tray icon
# Ubuntu dock is INTENTIONALLY absent from the list — dash-to-panel replaces it.
#
# favorite-apps drives what dash-to-panel pins in the taskbar row. Order
# matters — it is the visual left-to-right order. Every .desktop file must
# be resolvable from XDG_DATA_DIRS (system /usr/share/applications/,
# system flatpak exports /var/lib/flatpak/exports/share/applications/,
# per-user ~/.local/share/applications/).
install -d -m 0755 /etc/dconf/db/local.d
tee /etc/dconf/db/local.d/30-aiobi-taskbar-desktop > /dev/null << 'EOF'
# Aïobi OS — taskbar pins + desktop icons defaults

[org/gnome/shell]
enabled-extensions=['dash-to-panel@jderose9.github.com', 'user-theme@gnome-shell-extensions.gcampax.github.com', 'ding@rastersoft.com', 'ubuntu-appindicators@ubuntu.com']
favorite-apps=['org.gnome.Nautilus.desktop', 'brave-browser.desktop', 'org.gnome.Terminal.desktop', 'onlyoffice-desktopeditors.desktop', 'md.obsidian.Obsidian.desktop', 'aiobi-anythingllm.desktop', 'org.gnome.Settings.desktop']

[org/gnome/shell/extensions/ding]
show-home=true
show-trash=true
icon-size='standard'
start-corner='top-left'
show-drop-place=true
add-volumes-opposite=true
EOF
echo "  [dconf] /etc/dconf/db/local.d/30-aiobi-taskbar-desktop written"

# ----- 3) Populate /etc/skel/Desktop with default shortcuts ------------------
# Ding shows every .desktop / regular file present in the user Desktop
# folder as an icon on the wallpaper. Ship a small opinionated set — the
# user can add or remove any time via drag & drop.
SKEL_DESKTOP=/etc/skel/Desktop
install -d -m 0755 "$SKEL_DESKTOP"

# Curated default shortcuts. Each is copied ONLY if the source .desktop
# exists in the chroot at build time — silent skip otherwise, so the
# script does not fail on a chroot where a shortlist entry was not
# installed (e.g. Flatpak Obsidian not yet exported).
DEFAULT_SHORTCUTS=(
    "/usr/share/applications/brave-browser.desktop"
    "/usr/share/applications/onlyoffice-desktopeditors.desktop"
    "/usr/share/applications/aiobi-anythingllm.desktop"
    "/var/lib/flatpak/exports/share/applications/md.obsidian.Obsidian.desktop"
)

for src in "${DEFAULT_SHORTCUTS[@]}"; do
    if [ -f "$src" ]; then
        dst="$SKEL_DESKTOP/$(basename "$src")"
        cp -f "$src" "$dst"
        chmod 0755 "$dst"
        echo "  [skel] copied $(basename "$src") → $SKEL_DESKTOP/"
    else
        echo "  [skel] SKIP $(basename "$src") — source not present in chroot"
    fi
done

# ----- 4) dconf db compile (chroot-safe) -------------------------------------
# Script 06 (persistence) runs `dconf update` as its last act, so this
# script's keyfile lands in the compiled db without an extra recompile.
# If script 22 is run in isolation (not via run-all.sh), recompile now.
if command -v dconf >/dev/null 2>&1; then
    dconf update 2>/dev/null || true
    echo "  [dconf] db recompiled (safe idempotent)"
fi

echo "==> 22 done — Ding installed, taskbar pins + Aïobi shortcuts preseeded"
echo "    Effect on installed VM: every fresh user account boots with the"
echo "    Aïobi taskbar row + 4 desktop shortcuts + Home/Trash on the desktop."
