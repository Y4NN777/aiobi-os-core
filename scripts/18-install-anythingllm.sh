#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 18 — AnythingLLM desktop (offline chat + local RAG)
# ----------------------------------------------------------------------------
# Purpose : install AnythingLLM Desktop, the offline AI chat + document RAG
#           GUI that pairs with a local Ollama daemon. Distributed by
#           Mintplex Labs as a Linux AppImage only (no .deb / no Flatpak
#           / no Snap as of the current release).
#
# Delivers
#   - /opt/aiobi/AnythingLLMDesktop.AppImage  (executable, versioned by upstream)
#   - /usr/share/applications/aiobi-anythingllm.desktop  (menu entry)
#   - Optional AppArmor rule for Ubuntu 24.04+ (avoids SUID sandbox issue)
#
# Ollama endpoint pre-configuration
#   AnythingLLM Desktop stores per-user configuration under
#   ~/.config/anythingllm-desktop/. Because the model API endpoint is a
#   user setting rather than a system setting, the deploy of a
#   ready-to-use default file is handled through /etc/skel/ so newly
#   created accounts inherit the configuration pointing at the local
#   Ollama daemon on 127.0.0.1:11434 (script 15).
#
# Zero-data-leak: the app runs entirely locally; the pre-populated LLM
# provider config points at the loopback Ollama endpoint, so no query
# leaves the machine.
#
# References
#   - AnythingLLM Linux docs:
#     https://docs.anythingllm.com/installation-desktop/linux
#   - AppImage AppArmor issue on Ubuntu 24.04:
#     https://ubuntu.com/blog/ubuntu-23-10-restricted-unprivileged-user-namespaces
#
# Idempotent: AppImage is only re-downloaded if the marker is absent;
# the .desktop entry is overwritten every run.
# ============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi — 18-install-anythingllm.sh"

INSTALL_DIR=/opt/aiobi
APP_PATH="$INSTALL_DIR/AnythingLLMDesktop.AppImage"
MARKER="$INSTALL_DIR/.anythingllm-installed"

mkdir -p "$INSTALL_DIR"

# ----- 1) Download AppImage directly (bypass installer.sh) ------------------
# The upstream installer.sh refuses to run as root ("This script should not
# be run as root"), which our chroot context (where every step runs as root)
# cannot satisfy. We therefore fetch the AppImage from the same CDN the
# installer targets, with architecture detection matching the upstream
# script's own uname -m switch.
if [ ! -f "$MARKER" ] || [ ! -x "$APP_PATH" ]; then
    arch=$(uname -m)
    case "$arch" in
        arm64|aarch64) APPIMAGE_URL="https://cdn.anythingllm.com/latest/AnythingLLMDesktop-Arm64.AppImage" ;;
        *)             APPIMAGE_URL="https://cdn.anythingllm.com/latest/AnythingLLMDesktop.AppImage"       ;;
    esac
    echo "  fetching $APPIMAGE_URL"
    if curl -fL --retry 3 --retry-delay 5 -o "$APP_PATH" "$APPIMAGE_URL"; then
        chmod 755 "$APP_PATH"
        echo "  downloaded $APP_PATH ($(du -h "$APP_PATH" | awk '{print $1}'))"
    else
        rm -f "$APP_PATH"
        echo "  ⚠ download failed — the AppImage is not shipped in this ISO"
        echo "    the user can install it later with:"
        echo "      curl -fL -o ~/AnythingLLMDesktop.AppImage $APPIMAGE_URL"
        echo "      chmod +x ~/AnythingLLMDesktop.AppImage"
    fi

    if [ -x "$APP_PATH" ]; then
        touch "$MARKER"
    fi
else
    echo "  AnythingLLM already installed at $APP_PATH"
fi

# ----- 2) AppArmor rule for unprivileged user namespaces (Ubuntu 24.04+) ----
# Ubuntu 24.04 restricted unprivileged user namespaces by default. Electron-
# based AppImages (which AnythingLLM is) need a namespaced sandbox. Shipping
# a targeted AppArmor rule avoids requiring the user to run with --no-sandbox.
APPARMOR_DIR=/etc/apparmor.d
if [ -d "$APPARMOR_DIR" ]; then
    tee "$APPARMOR_DIR/aiobi-anythingllm" > /dev/null << EOF
# AppArmor profile for AnythingLLM Desktop (Aïobi OS)
# Allows the Electron sandbox to create unprivileged user namespaces.
abi <abi/4.0>,
include <tunables/global>

profile aiobi-anythingllm $APP_PATH flags=(unconfined) {
  userns,
  include if exists <local/aiobi-anythingllm>
}
EOF
    if command -v apparmor_parser >/dev/null 2>&1; then
        apparmor_parser -r "$APPARMOR_DIR/aiobi-anythingllm" 2>/dev/null || \
            echo "  apparmor_parser reload deferred (chroot mode)"
    fi
    echo "  installed AppArmor profile $APPARMOR_DIR/aiobi-anythingllm"
fi

# ----- 3) Ship .desktop entry -----------------------------------------------
APPS=/usr/share/applications
ICONS=/usr/share/icons/aiobi
install -d -m 0755 "$ICONS"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$HERE/icons/aiobi-ai-chat.svg" ]; then
    install -m 0644 "$HERE/icons/aiobi-ai-chat.svg" "$ICONS/aiobi-anythingllm.svg"
fi

tee "$APPS/aiobi-anythingllm.desktop" > /dev/null << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Aïobi AI (AnythingLLM)
Comment=Offline chat and document RAG with the local Aïobi AI daemon
Exec=$APP_PATH %U
Icon=$ICONS/aiobi-anythingllm.svg
Terminal=false
Categories=Utility;Chat;AudioVideo;
StartupWMClass=AnythingLLM
EOF
chmod 644 "$APPS/aiobi-anythingllm.desktop"
echo "  installed $APPS/aiobi-anythingllm.desktop"

# ----- 4) Ship default LLM-provider config into /etc/skel/ ------------------
# When a new user account is created (fresh install → user completes
# gnome-initial-setup), /etc/skel/ is copied into ~/. We drop a default
# AnythingLLM configuration pointing at the local Ollama endpoint so the
# app is ready to use on first launch without any user setup.
SKEL_CFG=/etc/skel/.config/anythingllm-desktop
mkdir -p "$SKEL_CFG"
tee "$SKEL_CFG/preferences.json" > /dev/null << 'EOF'
{
  "llm_provider": "ollama",
  "ollama_base_path": "http://127.0.0.1:11434",
  "ollama_chat_model_token_limit": 4096,
  "ollama_model_default": "qwen2.5:1.5b",
  "vector_db": "lancedb"
}
EOF
echo "  installed default preferences in /etc/skel/.config/anythingllm-desktop/"

update-desktop-database "$APPS" 2>/dev/null || \
    echo "  update-desktop-database deferred (chroot mode)"

# ----- 5) Verification --------------------------------------------------------
echo
echo "== Verification =="
[ -x "$APP_PATH" ] && echo "  ✓ $APP_PATH executable" || echo "  ⚠ $APP_PATH missing or non-executable"
[ -f "$APPS/aiobi-anythingllm.desktop" ] && echo "  ✓ .desktop entry present"
[ -f "$SKEL_CFG/preferences.json" ] && echo "  ✓ skel default preferences present"

echo "==> 18 done — AnythingLLM installed + configured against local Ollama"
