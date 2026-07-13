#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 12 — Wine + Proton (Windows interoperability)
# ----------------------------------------------------------------------------
# Purpose : install Wine 9.0 + i386 multiarch + Steam-installer (which pulls
#           Proton on first Steam launch) + GE-Proton (custom Proton variant,
#           standalone x86_64 binary) + MIME handlers for .exe / .msi so a
#           double-click in the file manager launches through Wine.
#
# Delivers : Wine + Proton installed silently inside the chroot; .exe
#            double-click routed through the compatibility layer; acceptance
#            criterion .exe execution satisfied.
#
# Architecture caveat (GE-Proton download)
#   The GitHub Releases API returns assets in non-deterministic order; a
#   naive `head -1` picks the aarch64 tarball roughly half the time. The
#   asset selector must therefore filter with `grep -v aarch64` before
#   `head -1`, or the downloaded binary will not execute on x86_64.
#
# Idempotent: apt install is idempotent; the GE-Proton tarball is only
# downloaded if not present; the symlink is recreated with `ln -f`.
#
# Ordering: standalone. Recommended AFTER 04-install-icons.sh (heavy apt use
# already done) and BEFORE 13-productivity-stack.sh.
# ============================================================================

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Must run as root (sudo)."; exit 1; }

RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
USER_HOME=$(getent passwd "$RUN_USER" | cut -d: -f6)

# --- 1. Enable multiverse (steam-installer lives there) + i386 multiarch ----
if ! grep -q "multiverse" /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null; then
    add-apt-repository -y multiverse
fi
dpkg --add-architecture i386
apt-get update -qq

# --- 2. Install Wine + winetricks + steam-installer -------------------------
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wine wine64 winetricks \
    steam-installer

# NOTE: we intentionally do NOT run `wineboot --init` in this script.
# Reason: it creates the ~/.wine/ tree at install time. If mksquashfs runs
# concurrently (as it does under some ISO-packaging tools that capture a
# running VM state), it hits a race and captures empty file placeholders
# in the ISO. Let Wine's prefix be created at the user's first `wine` call
# on the installed system — initialisation belongs to the user's session,
# not to the ISO build stage.

# --- 3. Install GE-Proton (standalone x86_64 tarball) -----------------------
# GloriousEggroll's Proton-GE fork — improved compat for games + apps vs
# vanilla Proton. Installed as standalone binary in /usr/local/bin so it
# can be invoked without Steam being launched.
mkdir -p "${USER_HOME}/.steam/root/compatibilitytools.d"

# CRITICAL: filter out aarch64 to pick x86_64
# GitHub Releases API returns assets in non-deterministic order — head -1
# picks the wrong arch ~50% of runs unless grep -v aarch64 first.
if ! ls -d "${USER_HOME}"/.steam/root/compatibilitytools.d/GE-Proton*/ 2>/dev/null | head -1 >/dev/null; then
    PROTON_URL=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest \
        | grep browser_download_url \
        | grep '.tar.gz"' \
        | grep -v aarch64 \
        | head -1 \
        | cut -d '"' -f 4)
    if [[ -z "$PROTON_URL" ]]; then
        echo "ERROR: could not resolve GE-Proton x86_64 tarball URL. GitHub API rate limit or offline?"
        exit 5
    fi
    echo "  fetching $PROTON_URL"
    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT
    wget -q -O "$TMPDIR/proton-ge.tar.gz" "$PROTON_URL"
    tar -xzf "$TMPDIR/proton-ge.tar.gz" -C "${USER_HOME}/.steam/root/compatibilitytools.d/"
    chown -R "$RUN_USER:$RUN_USER" "${USER_HOME}/.steam"
fi

# --- 4. CLI symlink for direct proton invocation (not via Steam) ------------
PROTON_BIN=$(ls -d "${USER_HOME}"/.steam/root/compatibilitytools.d/GE-Proton*/proton 2>/dev/null | head -1)
if [[ -n "$PROTON_BIN" ]]; then
    ln -sf "$PROTON_BIN" /usr/local/bin/proton
fi

# --- 5. MIME handlers — double-click .exe / .msi routes through Wine --------
# Applied system-wide via /etc/xdg/... (per-user via xdg-mime would only affect
# the running user; we want the default for every future user on the ISO).
mkdir -p /etc/xdg/mimeapps.list.d
tee /etc/xdg/mimeapps.list.d/aiobi-wine.list > /dev/null << 'EOF'
[Default Applications]
application/x-ms-dos-executable=wine.desktop
application/x-msi=wine.desktop
application/x-msdownload=wine.desktop
application/x-msdos-program=wine.desktop
EOF

# --- 6. Verification --------------------------------------------------------
echo "== Verification =="
echo "wine version:     $(wine --version 2>&1)"
echo "winetricks:       $(which winetricks)"
echo "steam:            $(which steam)"
echo "proton symlink:   $(readlink -f /usr/local/bin/proton 2>/dev/null || echo 'NOT LINKED')"
echo "GE-Proton dir:    $(ls -d "${USER_HOME}"/.steam/root/compatibilitytools.d/GE-Proton*/ 2>/dev/null | head -1)"
echo
echo "MIME handlers:"
cat /etc/xdg/mimeapps.list.d/aiobi-wine.list

echo "== 12-wine-proton-install.sh done =="
echo "Test: wget https://download.sysinternals.com/files/PSTools.zip && unzip PSTools.zip && wine PsInfo.exe /accepteula"
