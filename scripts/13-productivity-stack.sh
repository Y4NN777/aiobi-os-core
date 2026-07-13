#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — US-1.6 close — productivity stack
# ----------------------------------------------------------------------------
# Purpose : install the Sprint 1 productivity app set:
#           OnlyOffice (.deb from vendor), Brave (vendor apt repo),
#           VLC + Flameshot (Ubuntu universe), PeaZip + AppFlowy (Flatpak).
#
# Closes  : US-1.6 CA-1 (OnlyOffice + .docx test) — milestone S1 passage #5.
#           US-1.6 CA-2 (AppFlowy pre-installed).
#           US-1.6 CA-3 (Brave, VLC, PeaZip, Flameshot pre-configured).
#
# References :
#   - Log 5 §2.15 (this fix documented + demo.docx test)
#   - Log 5 §5 Issue 31 (apt install -y hangs on OnlyOffice EULA prompt)
#   - Log 5 §5 Issue 32 (peazip absent from Ubuntu 24.04 repos → Flatpak fallback)
#
# Idempotent: apt install is idempotent; wget only if not already downloaded;
# flatpak install --if-not-exists.
#
# Ordering: standalone. Recommended late in the pipeline (after 04-install-icons
# because both use apt heavily, and after 11-apt-brand-alias if you want the
# alias visible during install output).
# ============================================================================

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Must run as root (sudo)."; exit 1; }

# Suppress apt EULA prompts (OnlyOffice ships an interactive EULA that
# blocks apt install -y otherwise — Issue 31).
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

# --- 1. OnlyOffice (vendor .deb, no maintained PPA for 24.04) ---------------
OO_DEB=/tmp/onlyoffice-desktopeditors.deb
if ! dpkg -l | grep -q "^ii  onlyoffice-desktopeditors"; then
    if [[ ! -f "$OO_DEB" ]]; then
        wget -q -O "$OO_DEB" \
            "https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors_amd64.deb"
    fi
    apt-get install -y "$OO_DEB" 2>&1 | tail -8
fi

# --- 2. Brave — vendor apt repo (official signed) ---------------------------
if ! dpkg -l | grep -q "^ii  brave-browser"; then
    curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
        https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null << 'EOF'
deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main
EOF
    apt-get update -qq
    apt-get install -y brave-browser
fi

# --- 3. VLC + Flameshot (Ubuntu universe, straight apt) ---------------------
apt-get install -y vlc flameshot

# --- 4. Flatpak infrastructure ----------------------------------------------
# PeaZip and AppFlowy both ship as Flatpaks from Flathub — Ubuntu 24.04 does
# not package PeaZip in its repos (Issue 32) and AppFlowy is Rust-based with
# no official .deb, only Flatpak/AppImage.
apt-get install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# --- 5. PeaZip (Flatpak) ----------------------------------------------------
flatpak install -y flathub io.github.peazip.PeaZip

# --- 6. AppFlowy (Flatpak) --------------------------------------------------
flatpak install -y flathub io.appflowy.AppFlowy

# --- 7. Verification --------------------------------------------------------
echo "== Verification =="
echo
echo "apt-installed (dpkg -l | grep -E '^ii  (onlyoffice|brave|vlc|flameshot)'):"
dpkg -l | grep -E '^ii  (onlyoffice|brave|vlc|flameshot)' | awk '{printf "  %-40s %s\n", $2, $3}'
echo
echo "flatpaks:"
flatpak list --app 2>/dev/null | grep -Ei "peazip|appflowy" || echo "  none listed"
echo
echo "Launcher binaries:"
for cmd in onlyoffice-desktopeditors brave-browser vlc flameshot; do
    printf "  %-30s %s\n" "$cmd" "$(which "$cmd" 2>/dev/null || echo 'NOT FOUND')"
done

# Cleanup deb
rm -f "$OO_DEB"

echo "== 13-productivity-stack.sh done =="
echo "Test .docx: mkdir -p ~/docx-tests && cd ~/docx-tests && wget -q -O demo.docx https://calibre-ebook.com/downloads/demos/demo.docx && onlyoffice-desktopeditors demo.docx &"
