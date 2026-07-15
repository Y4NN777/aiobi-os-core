#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Step 22 — Taskbar pins + desktop icons + first-login trust
# =============================================================================
# Purpose : deliver a Windows-familiar first-boot experience on Aïobi OS.
#   (a) install Desktop Icons NG (Ding) — GNOME 3.28+ removed Nautilus-
#       desktop, Ding is the maintained replacement that renders files
#       and .desktop shortcuts on the wallpaper.
#   (b) preseed a dconf keyfile with:
#         - enabled-extensions = dash-to-panel + user-theme + Ding
#           (Ding EXPLICITLY listed — on the user's VM Ding was running
#           but absent from `gsettings get enabled-extensions` output,
#           suggesting it was enabled via Extensions Manager GUI which
#           writes elsewhere; without explicit listing a fresh install
#           would install Ding but never activate it → no desktop icons)
#         - favorite-apps = the six taskbar pins the user chose
#         - Ding config (icon-size, corner, home/trash visibility)
#   (c) copy the thirteen default .desktop shortcuts the user chose on
#       her VM into /etc/skel/Desktop/. Sources are silently skipped if
#       missing from the chroot (e.g. Flatpak app not yet exported).
#   (d) ship a per-user systemd oneshot aiobi-desktop-trust.service that
#       runs at first login and calls `gio set metadata::trusted true`
#       on every ~/Desktop/*.desktop file so Ding does not display the
#       "grey icon with a cross" (untrusted) warning until the user
#       manually right-clicks "Allow Launching". Enables itself via a
#       symlink in /etc/skel/.config/systemd/user/ so every account
#       created by Subiquity inherits it.
#
# The dconf keyfile lands under /etc/dconf/db/local.d/ and is compiled
# into the system db by script 06 (persistence) which runs AFTER this
# script. This script also calls `dconf update` opportunistically so
# isolated re-runs (outside run-all.sh) still take effect.
#
# Idempotent: apt install skips if already latest; keyfile is
# overwritten every run; /etc/skel/Desktop/ copies are `cp -f`
# overwrites; systemd unit + script are `install -m` overwrites.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi — 22-taskbar-desktop-defaults.sh"

# ----- 1) Install Ding (Desktop Icons NG) ------------------------------------
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    gnome-shell-extension-desktop-icons-ng
echo "  [apt] gnome-shell-extension-desktop-icons-ng installed"

# ----- 2) Preseed dconf keyfile ----------------------------------------------
# Values captured verbatim from the user's converged VM layout (2026-07-16):
#   gsettings get org.gnome.shell favorite-apps        → 6 apps in order
#   dconf dump   /org/gnome/shell/extensions/ding/     → 5 config keys
#   gsettings get org.gnome.shell enabled-extensions   → dash-to-panel +
#                                                        user-theme (Ding
#                                                        added explicitly
#                                                        below — see header)
# Ubuntu dock intentionally absent — dash-to-panel replaces it.
install -d -m 0755 /etc/dconf/db/local.d
tee /etc/dconf/db/local.d/30-aiobi-taskbar-desktop > /dev/null << 'EOF'
# Aïobi OS — taskbar pins + desktop icons defaults

[org/gnome/shell]
enabled-extensions=['dash-to-panel@jderose9.github.com', 'user-theme@gnome-shell-extensions.gcampax.github.com', 'ding@rastersoft.com']
favorite-apps=['org.gnome.Nautilus.desktop', 'onlyoffice-desktopeditors.desktop', 'org.flameshot.Flameshot.desktop', 'aiobi-anythingllm.desktop', 'vlc.desktop', 'brave-browser.desktop']

[org/gnome/shell/extensions/ding]
check-x11wayland=true
icon-size='standard'
show-home=true
show-trash=true
start-corner='top-left'
EOF
echo "  [dconf] /etc/dconf/db/local.d/30-aiobi-taskbar-desktop written"

# ----- 3) First-login trust helper + systemd user oneshot --------------------
# Ding refuses to launch a .desktop file that has not been marked trusted
# via the gvfs metadata database attribute metadata::trusted=true. The
# `gio` call REQUIRES a running gvfs session (chroot cannot provide one),
# so the trust step is deferred to the user's first login via a systemd
# user oneshot. The oneshot marks itself done via ~/.local/share/aiobi-
# desktop-trusted so the second login is a no-op.
install -d -m 0755 /usr/local/bin
tee /usr/local/bin/aiobi-desktop-trust > /dev/null << 'EOF'
#!/bin/bash
# Aïobi OS — first-login helper: trust every .desktop in the user's
# Desktop folder so Ding renders them as clean icons instead of the
# grey-with-a-cross "not trusted" placeholder.
set -e
DESKTOP_DIR="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
[ -d "$DESKTOP_DIR" ] || exit 0
for f in "$DESKTOP_DIR"/*.desktop; do
    [ -f "$f" ] || continue
    chmod +x "$f" 2>/dev/null || true
    gio set -t string "$f" metadata::trusted true 2>/dev/null || true
done
EOF
chmod 0755 /usr/local/bin/aiobi-desktop-trust
echo "  installed /usr/local/bin/aiobi-desktop-trust"

install -d -m 0755 /etc/systemd/user
tee /etc/systemd/user/aiobi-desktop-trust.service > /dev/null << 'EOF'
[Unit]
Description=Aïobi OS — trust default Desktop shortcuts at first login
ConditionPathExists=!%h/.local/share/aiobi-desktop-trusted
After=default.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/aiobi-desktop-trust
ExecStartPost=/bin/mkdir -p %h/.local/share
ExecStartPost=/usr/bin/touch %h/.local/share/aiobi-desktop-trusted
RemainAfterExit=no

[Install]
WantedBy=default.target
EOF
echo "  installed /etc/systemd/user/aiobi-desktop-trust.service"

# Enable per-user via skel — every account Subiquity creates inherits
# the symlink in ~/.config/systemd/user/default.target.wants/.
SKEL_UNIT_WANTS=/etc/skel/.config/systemd/user/default.target.wants
install -d -m 0755 "$SKEL_UNIT_WANTS"
ln -sf /etc/systemd/user/aiobi-desktop-trust.service \
       "$SKEL_UNIT_WANTS/aiobi-desktop-trust.service"
echo "  enabled aiobi-desktop-trust.service via /etc/skel"

# ----- 4) Populate /etc/skel/Desktop with default shortcuts ------------------
# 13 candidates captured from the user's VM Desktop layout. Sources are
# checked for existence; missing ones are silently skipped so the script
# tolerates any chroot where a specific app was not installed (e.g.
# Flatpak Obsidian may not be exported before script 13 has run all its
# steps in a re-ordered invocation).
SKEL_DESKTOP=/etc/skel/Desktop
install -d -m 0755 "$SKEL_DESKTOP"

DEFAULT_SHORTCUTS=(
    /usr/share/applications/aiobi-anythingllm.desktop
    /usr/share/applications/brave-browser.desktop
    /usr/share/applications/onlyoffice-desktopeditors.desktop
    /usr/share/applications/org.flameshot.Flameshot.desktop
    /usr/share/applications/org.gnome.Calculator.desktop
    /usr/share/applications/org.gnome.Calendar.desktop
    /usr/share/applications/org.gnome.Nautilus.desktop
    /usr/share/applications/org.gnome.Settings.desktop
    /usr/share/applications/org.gnome.Terminal.desktop
    /usr/share/applications/org.gnome.TextEditor.desktop
    /usr/share/applications/steam.desktop
    /usr/share/applications/vlc.desktop
    /var/lib/flatpak/exports/share/applications/md.obsidian.Obsidian.desktop
)

copied=0
skipped=0
for src in "${DEFAULT_SHORTCUTS[@]}"; do
    if [ -f "$src" ]; then
        dst="$SKEL_DESKTOP/$(basename "$src")"
        cp -f "$src" "$dst"
        chmod 0755 "$dst"
        copied=$((copied + 1))
    else
        skipped=$((skipped + 1))
        echo "  [skel] SKIP $(basename "$src") — source not present in chroot"
    fi
done
echo "  [skel] copied $copied shortcuts to $SKEL_DESKTOP ($skipped skipped)"

# ----- 5) dconf db compile (chroot-safe) -------------------------------------
# Script 06 also runs `dconf update` at the tail of the pipeline, so
# this second call is idempotent — it only matters when step 22 is
# invoked in isolation for testing.
if command -v dconf >/dev/null 2>&1; then
    dconf update 2>/dev/null || true
    echo "  [dconf] db recompiled (safe idempotent)"
fi

echo "==> 22 done — Ding installed, taskbar pins + Aïobi shortcuts + trust service preseeded"
echo "    Effect on installed VM: every fresh user account boots with the"
echo "    Aïobi taskbar row (6 pins), $copied desktop shortcuts, Home + Trash"
echo "    on the desktop, and the trust helper runs once at first login to"
echo "    mark every .desktop as trusted (no grey-cross icons)."
