#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 13 — Productivity stack
# ----------------------------------------------------------------------------
# Purpose : purge Ubuntu 24.04's pre-installed LibreOffice suite, then
#           install the Aïobi productivity application set:
#             OnlyOffice (.deb from vendor) as the primary office suite,
#             Brave (vendor apt repo) as alternate browser,
#             VLC + Flameshot (Ubuntu universe),
#             PeaZip + AppFlowy + Obsidian (Flatpak from Flathub, none
#             packaged natively in Ubuntu 24.04).
#
# Delivers : OnlyOffice as sole and default .docx handler, Brave as
#            alternate browser, VLC + Flameshot + PeaZip + AppFlowy +
#            Obsidian pre-installed.
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

# --- 0. Purge LibreOffice ---------------------------------------------------
# Ubuntu 24.04 desktop pre-installs the full LibreOffice suite (~600 MB
# of core + ~200 MB of dictionaries and translation packs). Aïobi ships
# OnlyOffice as the primary office suite; shipping both in parallel is
# redundant, inflates the ISO, and populates the GNOME app grid with
# duplicate Writer / Calc / Impress / Draw / Math / Startcenter entries.
# Purge LibreOffice and its language/hyphenation dependencies before
# installing OnlyOffice so the ISO ships exactly one office suite.
apt-get purge -y 'libreoffice-*' 'mythes-*' 'hyphen-*' \
    'libuno-*' uno-libs-private ure 2>/dev/null || true
apt-get autoremove -y --purge 2>/dev/null || true

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

# Flatpak resilience helpers.
#
# Flathub CDN throughput is variable; a single `flatpak install` can stall
# to sub-100 kB/s under load. Worse, when a runtime dependency fails to
# fetch mid-install, Flatpak emits a `Warning: Failed to install …` but
# continues with the other dependencies and exits with status 0 anyway.
# A naive `if flatpak install; then success` therefore misses the partial
# failure: the app is registered but a critical runtime (typically
# org.freedesktop.Platform.GL.default) is absent, which breaks the app
# at first launch.
#
# We defend against this with a two-step wrapper:
#   1. Run the install under a wall-clock timeout.
#   2. Verify that the app AND the critical runtimes are actually present
#      via `flatpak list --columns=ref`. If any are missing, treat the
#      attempt as a failure and go through `flatpak repair --system`
#      before retrying (up to 3 attempts total).

flatpak_ref_installed() {
    # Returns success if the given ref (app or runtime) is installed.
    # We use --columns=ref which prints just the ref column, then match
    # by prefix so branch differences (e.g. //25.08 vs //stable) do not
    # trip the check.
    flatpak list --columns=ref 2>/dev/null | awk -F/ '{print $1}' | grep -Fxq "$1"
}

verify_flatpak_install() {
    local app="$1"
    local critical
    if ! flatpak_ref_installed "$app"; then
        echo "  ✗ post-check: app $app not installed"
        return 1
    fi
    for critical in \
        org.freedesktop.Platform \
        org.freedesktop.Platform.GL.default
    do
        if ! flatpak_ref_installed "$critical"; then
            echo "  ✗ post-check: critical runtime $critical missing"
            return 1
        fi
    done
    echo "  ✓ post-check: $app + critical runtimes all present"
    return 0
}

flatpak_install_with_retry() {
    local remote="$1"
    local app="$2"
    local attempt rc
    for attempt in 1 2 3; do
        echo "  flatpak install attempt $attempt: $app"
        timeout 900 flatpak install -y --noninteractive "$remote" "$app"
        rc=$?
        if [ "$rc" -eq 0 ] && verify_flatpak_install "$app"; then
            return 0
        fi
        echo "  attempt $attempt failed (rc=$rc or post-check failed) — repairing before retry"
        flatpak repair --system 2>/dev/null || true
        sleep 5
    done
    echo "  ⚠ giving up on $app after 3 attempts (Flathub CDN unreachable or too slow)"
    echo "    manual recovery command:"
    echo "      flatpak install -y --or-update flathub $app"
    return 1
}

# --- 5. PeaZip (Flatpak) ----------------------------------------------------
flatpak_install_with_retry flathub io.github.peazip.PeaZip || true

# --- 6. AppFlowy (Flatpak) --------------------------------------------------
flatpak_install_with_retry flathub io.appflowy.AppFlowy || true

# --- 7. Obsidian (Flatpak, local-first Markdown knowledge base) -------------
# Obsidian stores every note as a plain Markdown file in a user-chosen
# local vault. No cloud sync is required or activated by default, which
# aligns with the Aïobi zero-data-leak posture more cleanly than
# AppFlowy (whose onboarding flow prompts for a cloud account). Both are
# shipped so the user can pick between them.
flatpak_install_with_retry flathub md.obsidian.Obsidian || true

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
