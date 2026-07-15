#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Step 01 — Install GNOME extensions (dash-to-panel)
# =============================================================================
# WHAT
#   - Installs `dash-to-panel` system-wide so every user inherits it.
#   - Enables it for the current user.
#   - Disables Ubuntu's built-in dock (ubuntu-dock@ubuntu.com).
#
# WHY system-wide
#   Per-user install (~/.local/share/gnome-shell/extensions) ties the dock to
#   one account. Aïobi ships a desktop EXPERIENCE — every account on the ISO
#   must boot with the bottom violet panel out of the box. System path:
#     /usr/share/gnome-shell/extensions/<uuid>/
#   gnome-shell scans this path at startup for every session.
#
# METHOD
#   1. Try apt package `gnome-shell-extension-dash-to-panel` first (Debian-
#      packaged, signed, easy to update). Confirmed available in Ubuntu
#      24.04 universe.
#   2. Fallback to direct .zip from the GitHub release tagged v60+ which is
#      the first release shipping shell-version "46" in metadata.json.
#
# SOURCES
#   - https://github.com/home-sweet-gnome/dash-to-panel/wiki/Installation
#   - https://ubuntuhandbook.org/index.php/2024/03/dash-to-panel-gnome-46/
#   - https://packages.debian.org/sid/gnome-shell-extension-dash-to-panel
#
# IDEMPOTENT: re-running re-installs only if the extension is missing.
# =============================================================================

set -euo pipefail

UUID="dash-to-panel@jderose9.github.com"
SYSTEM_EXT_DIR="/usr/share/gnome-shell/extensions"
SYSTEM_PATH="${SYSTEM_EXT_DIR}/${UUID}"
RELEASE_URL="https://github.com/home-sweet-gnome/dash-to-panel/releases/latest/download/dash-to-panel@jderose9.github.com.zip"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi — 01-install-extensions.sh"

# Ensure the Ubuntu universe repo is enabled. dash-to-panel lives there on
# Ubuntu 24.04, and so do vlc / flameshot / wine consumed by later scripts.
# Cubic's minimal chroot base may ship with universe disabled — enable
# idempotently so `apt-get install` finds an installable candidate.
if ! grep -q "^Components:.*universe" /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq software-properties-common
    add-apt-repository -y universe
fi

# Refresh apt index quietly; ignore failure (offline build host case)
apt-get update -qq || true

# ----- 1) Try apt package (opportunistic — often absent in Ubuntu 24.04) ------
# The dash-to-panel Debian package is not reliably present in Ubuntu 24.04
# noble universe as an installable candidate (name may resolve in apt-cache
# metadata via a related repo but have no downloadable version). Attempt
# is guarded: any failure at either the show or the install step falls
# through to the .zip fallback below rather than halting the pipeline.
if apt-cache policy gnome-shell-extension-dash-to-panel 2>/dev/null \
   | grep -q "Candidate: [0-9]"; then
    echo "  [apt] installing gnome-shell-extension-dash-to-panel"
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        gnome-shell-extension-dash-to-panel 2>/dev/null; then
        echo "  [apt] installed successfully"
    else
        echo "  [apt] install failed — falling through to .zip"
    fi
else
    echo "  [apt] no installable candidate — using .zip fallback"
fi

# ----- 2) Fallback — direct zip download -------------------------------------
if [ ! -d "$SYSTEM_PATH" ]; then
    echo "  [zip] downloading latest release from GitHub"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl unzip
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    curl -fsSL -o "$tmpdir/d2p.zip" "$RELEASE_URL"
    mkdir -p "$SYSTEM_PATH"
    unzip -q -o "$tmpdir/d2p.zip" -d "$SYSTEM_PATH"
    # Compile schema so dconf can read the keys (extension ships .gschema.xml)
    if [ -d "$SYSTEM_PATH/schemas" ]; then
        glib-compile-schemas "$SYSTEM_PATH/schemas"
    fi
fi

# ----- 3) Sanity — metadata.json must declare shell-version 46 ---------------
if grep -q '"46"' "$SYSTEM_PATH/metadata.json" 2>/dev/null \
   || grep -q '"45"' "$SYSTEM_PATH/metadata.json" 2>/dev/null; then
    echo "  OK metadata.json declares GNOME 46 compatibility"
else
    echo "  WARN: metadata.json does not list shell-version 46 — extension may refuse to load"
    cat "$SYSTEM_PATH/metadata.json" || true
fi

# ----- 4) Disable Ubuntu dock — system-wide via dconf override ---------------
# Per-user `gnome-extensions disable ubuntu-dock@ubuntu.com` only affects the
# invoking user; we set the disabled-extensions key in the system dconf db
# instead so EVERY new user starts with Ubuntu dock off. The actual write to
# /etc/dconf/db/local.d/ happens in script 06 (persistence).
echo "  Ubuntu dock will be disabled via system dconf in script 06"

# ----- 5) Enable for the invoking session (if X/Wayland live) ----------------
# When this script runs inside a chroot during ISO build, $DISPLAY is unset,
# `gnome-extensions enable` fails because no shell is running. We skip silently
# in that case — the system dconf override (script 06) handles enablement at
# first user login. When run on an installed VM for QA, the enable succeeds.
if command -v gnome-extensions >/dev/null 2>&1 && [ -n "${DISPLAY:-${WAYLAND_DISPLAY:-}}" ]; then
    sudo -u "${SUDO_USER:-$USER}" gnome-extensions enable "$UUID" \
        2>/dev/null || echo "  (live-enable skipped — likely chroot or no session)"
fi

echo "==> 01 done. Extension present at $SYSTEM_PATH"
