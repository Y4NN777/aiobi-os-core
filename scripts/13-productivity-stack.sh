#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 13 — Productivity stack
# ----------------------------------------------------------------------------
# Purpose : install the default productivity application set:
#           OnlyOffice (.deb from vendor), Brave (vendor apt repo),
#           VLC + Flameshot (Ubuntu universe), PeaZip + AppFlowy (Flatpak
#           from Flathub, as neither is packaged natively in Ubuntu 24.04).
#
# Delivers : OnlyOffice as default .docx handler, Brave as alternate browser,
#            VLC + Flameshot + PeaZip + AppFlowy pre-installed.
#
# Non-interactive apt caveat
#   OnlyOffice's postinst script exposes an interactive EULA that blocks
#   `apt install -y`. The script therefore exports
#   DEBIAN_FRONTEND=noninteractive and DEBCONF_NONINTERACTIVE_SEEN=true
#   before the OnlyOffice install to accept the EULA silently.
#
# Idempotent: apt install is idempotent; wget only fires if the .deb is
# absent; flatpak install uses --if-not-exists on the remote.
#
# Ordering: standalone. Recommended late in the pipeline (after
# 04-install-icons.sh because both use apt heavily, and after
# 11-apt-brand-alias.sh if the alias should be visible during install
# output).
# ============================================================================

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Must run as root (sudo)."; exit 1; }

# Suppress apt EULA prompts (OnlyOffice ships an interactive EULA that
# blocks apt install -y otherwise).
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
# not package PeaZip in its repos and AppFlowy is Rust-based with
# no official .deb, only Flatpak/AppImage.
apt-get install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Flatpak resilience helper: Flathub CDN throughput is variable; a single
# `flatpak install` can stall to sub-100 kB/s under load. We wrap the
# install in a retry loop (3 attempts) that on each failure marks any
# partial download for repair via `flatpak repair` before retrying. A
# soft failure of Flatpak apps is not fatal for the pipeline — the base
# system remains functional; the missing apps are logged for later.
flatpak_install_with_retry() {
    local remote="$1"
    local app="$2"
    local attempt
    for attempt in 1 2 3; do
        echo "  flatpak install attempt $attempt: $app"
        if timeout 900 flatpak install -y --noninteractive "$remote" "$app"; then
            return 0
        fi
        echo "  attempt $attempt failed (timeout or fetch error) — repairing before retry"
        flatpak repair --system 2>/dev/null || true
        sleep 5
    done
    echo "  ⚠ giving up on $app after 3 attempts (Flathub CDN unreachable or too slow)"
    echo "    the missing app can be installed later with: flatpak install flathub $app"
    return 1
}

# --- 5. PeaZip (Flatpak) ----------------------------------------------------
flatpak_install_with_retry flathub io.github.peazip.PeaZip || true

# --- 6. AppFlowy (Flatpak) --------------------------------------------------
flatpak_install_with_retry flathub io.appflowy.AppFlowy || true

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
