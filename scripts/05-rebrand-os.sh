#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — US-1.4 / Step 05 — Rebrand the OS identity (About panel)
# =============================================================================
# WHAT
#   Updates the three files GNOME Settings → About reads from:
#     /etc/os-release        ← user-mutable runtime fingerprint
#     /usr/lib/os-release    ← vendor canonical (often a symlink target)
#     /etc/lsb-release       ← legacy LSB tool surface
#   Plus /etc/issue + /etc/issue.net for console / SSH banners.
#
# WHY 3 files
#   GNOME 46 control-center reads PRETTY_NAME from /etc/os-release first.
#   Tooling that pre-dates systemd (apt scripts, deb packagers) still calls
#   `lsb_release -d` which reads /etc/lsb-release directly. Some Ubuntu
#   packages source /usr/lib/os-release on upgrade — leaving it stock means
#   the next dist-upgrade silently restores "Ubuntu" in the About panel.
#
# WHY preserve VERSION_ID + ID_LIKE
#   The Ubuntu ID is what apt repositories and snap match against to serve
#   binaries. Rewriting `ID=ubuntu` to `ID=aiobi` breaks pkg.go.dev,
#   third-party PPAs and Snap channel matching. We KEEP ID/VERSION_ID/UBUNTU_CODENAME
#   and override only the display fields (NAME / PRETTY_NAME / HOME_URL /
#   SUPPORT_URL / BUG_REPORT_URL / LOGO).
#
# UTF-8 ï handling
#   Heredoc + `cat` would normally pass through fine, but earlier work in
#   this repo hit shells stripping the tréma (Log_of_day_3 §5 / Issue 18).
#   We reconstruct ï via `printf '\xc3\xaf'` and inject the byte sequence
#   directly, then verify with `grep -P` that the bytes round-tripped.
#
# SOURCES
#   - https://www.freedesktop.org/software/systemd/man/os-release.html
#   - https://manpages.ubuntu.com/manpages/noble/man1/lsb_release.1.html
#   - GNOME control-center about panel:
#     https://gitlab.gnome.org/GNOME/gnome-control-center/-/blob/main/panels/about/cc-about-page.c
#
# IDEMPOTENT: writes fresh files on every run; backs up originals on first run.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi US-1.4 / 05-rebrand-os.sh"

# Reconstruct ï as the literal UTF-8 byte pair (0xc3 0xaf) — bypasses any
# upstream encoding mangling.
I_TREMA=$(printf '\xc3\xaf')
BRAND="A${I_TREMA}obi"
PRETTY="A${I_TREMA}obi OS 1.0"

# Source Ubuntu's existing VERSION_ID + UBUNTU_CODENAME so apt/snap continue
# to resolve the correct base.
. /etc/os-release
UBUNTU_VERSION_ID="${VERSION_ID:-24.04}"
UBUNTU_CODENAME="${UBUNTU_CODENAME:-noble}"

# ----- 1) /etc/os-release ----------------------------------------------------
[ -f /etc/os-release.aiobi.bak ] || cp /etc/os-release /etc/os-release.aiobi.bak
cat > /etc/os-release << EOF
PRETTY_NAME="$PRETTY"
NAME="$BRAND OS"
VERSION_ID="$UBUNTU_VERSION_ID"
VERSION="1.0 (based on Ubuntu $UBUNTU_VERSION_ID $UBUNTU_CODENAME)"
VERSION_CODENAME=aiobi
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://aiobi.com/"
SUPPORT_URL="https://aiobi.com/support"
BUG_REPORT_URL="https://aiobi.com/bugs"
PRIVACY_POLICY_URL="https://aiobi.com/privacy"
UBUNTU_CODENAME=$UBUNTU_CODENAME
LOGO=aiobi-logo
EOF
chmod 644 /etc/os-release
echo "  wrote /etc/os-release"

# ----- 2) /usr/lib/os-release (vendor canonical) -----------------------------
# Some Ubuntu releases symlink /etc/os-release → /usr/lib/os-release. If so,
# /etc/os-release write above just rewrote the symlink target. Detect and
# replace as needed.
if [ -L /usr/lib/os-release ]; then
    : # Symlink to /etc — already updated
elif [ -f /usr/lib/os-release ]; then
    [ -f /usr/lib/os-release.aiobi.bak ] || cp /usr/lib/os-release /usr/lib/os-release.aiobi.bak
    cp /etc/os-release /usr/lib/os-release
    echo "  mirrored /usr/lib/os-release"
fi

# ----- 3) /etc/lsb-release ---------------------------------------------------
[ -f /etc/lsb-release.aiobi.bak ] || cp /etc/lsb-release /etc/lsb-release.aiobi.bak 2>/dev/null || true
cat > /etc/lsb-release << EOF
DISTRIB_ID=Ubuntu
DISTRIB_RELEASE=$UBUNTU_VERSION_ID
DISTRIB_CODENAME=$UBUNTU_CODENAME
DISTRIB_DESCRIPTION="$PRETTY"
EOF
chmod 644 /etc/lsb-release
echo "  wrote /etc/lsb-release"

# ----- 4) Console + SSH login banners ----------------------------------------
echo "$PRETTY \\n \\l" > /etc/issue
echo "$PRETTY" > /etc/issue.net

# ----- 5) Verify the tréma survived the round-trip ---------------------------
PROBE="A$(printf '\xc3\xaf')obi"
if grep -q "$PROBE" /etc/os-release && grep -q "$PROBE" /etc/lsb-release; then
    echo "  UTF-8 tréma round-trip OK"
else
    echo "  ERROR: tréma lost in transit — check shell encoding"
    exit 1
fi

# =============================================================================
# Day 5 additions (Log 5 §2.10 + §2.11)
# =============================================================================

# ----- 6) Default hostname (Bug D — Log 5 §2.3) -----------------------------
# Ubuntu installer templates the hostname as `firstname-lastname-<QEMU-machine>`
# by default. We set an Aïobi-branded baseline in the chroot; the installer
# may still overwrite at install time if the user provides input in the
# Ubiquity wizard — the first-boot service below (§7) restores it if needed.
hostnamectl set-hostname aiobi 2>/dev/null || echo aiobi > /etc/hostname
sed -i '/127\.0\.1\.1/d' /etc/hosts 2>/dev/null || true
echo "127.0.1.1  aiobi" >> /etc/hosts
echo "  hostname set to 'aiobi'"

# ----- 7) GRUB_DISTRIBUTOR (Log 5 §2.11) ------------------------------------
# Without this, update-grub falls back to `lsb_release -i -s` which returns
# unpredictable values on rebranded systems (observed: `GNU/Linux` as menu
# entry prefix). Explicit distributor = correct menu labels.
if [ -f /etc/default/grub ]; then
    [ -f /etc/default/grub.aiobi.bak ] || cp /etc/default/grub /etc/default/grub.aiobi.bak
    if grep -q "^GRUB_DISTRIBUTOR=" /etc/default/grub; then
        sed -i "s|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR=\"A${I_TREMA}obi OS\"|" /etc/default/grub
    else
        echo "GRUB_DISTRIBUTOR=\"A${I_TREMA}obi OS\"" >> /etc/default/grub
    fi
    # update-grub may fail inside chroot (no /dev/vda mounted) — non-fatal
    update-grub 2>/dev/null || echo "  update-grub deferred (chroot mode)"
    echo "  GRUB_DISTRIBUTOR set"
fi

# ----- 8) MOTD debloat (Log 5 §2.11) ----------------------------------------
# /etc/update-motd.d/ contains 11 Ubuntu-branded scripts. Neutralise via
# `chmod -x` (safer than deletion — Ubuntu package updates restore the +x bit
# on the individual scripts; we can re-neutralise via re-running this
# script). Then ship a lightweight Aïobi header.
for f in /etc/update-motd.d/00-header \
         /etc/update-motd.d/10-help-text \
         /etc/update-motd.d/50-motd-news \
         /etc/update-motd.d/91-contract-ua-esm-status \
         /etc/update-motd.d/91-release-upgrade \
         /etc/update-motd.d/95-hwe-eol; do
    [ -f "$f" ] && chmod -x "$f"
done

tee /etc/update-motd.d/00-aiobi-header > /dev/null << EOF
#!/bin/sh
printf '\n  Welcome to A${I_TREMA}obi OS 1.0\n'
printf '  The AI-native operating system.\n\n'
EOF
chmod +x /etc/update-motd.d/00-aiobi-header
echo "  MOTD debloated, Aïobi header shipped"

# ----- 9) Ubuntu Advantage notification kill (Log 5 §2.11) ------------------
# /etc/xdg/autostart/ubuntu-advantage-notification.desktop autostarts a
# Canonical popup nagging about Ubuntu Pro. Append Hidden=true to disable
# without deleting (delete would be restored by ubuntu-advantage-tools
# package updates; Hidden=true survives).
UA_NOTIF=/etc/xdg/autostart/ubuntu-advantage-notification.desktop
if [ -f "$UA_NOTIF" ]; then
    if ! grep -q "^Hidden=true" "$UA_NOTIF"; then
        tee -a "$UA_NOTIF" > /dev/null << 'EOF'
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
        echo "  ubuntu-advantage-notification disabled"
    fi
fi

# ----- 10) First-boot systemd oneshot — PRETTY_NAME Cubic-resistance --------
# Cubic Generate overwrites /etc/os-release's PRETTY_NAME field at ISO build
# time with a build timestamp string ("Ubuntu 24.04.4 1.0.0-2026.04.28 (Cubic
# YYYY-MM-DD hh:mm)") — see Log 5 §5 Issue 26. This service reverts to
# Aïobi PRETTY_NAME at first user boot then disables itself.
tee /etc/systemd/system/aiobi-firstboot-rebrand.service > /dev/null << 'EOF'
[Unit]
Description=Aïobi OS — first-boot rebrand of PRETTY_NAME (Cubic-resistance)
Before=display-manager.service
ConditionPathExists=!/var/lib/aiobi-firstboot-done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/aiobi-firstboot-rebrand.sh
ExecStartPost=/usr/bin/touch /var/lib/aiobi-firstboot-done
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

tee /usr/local/sbin/aiobi-firstboot-rebrand.sh > /dev/null << 'EOF'
#!/usr/bin/env bash
# Aïobi OS — first-boot rebrand (Cubic PRETTY_NAME overwrite recovery)
set -e
I_TREMA=$(printf '\xc3\xaf')
PRETTY="A${I_TREMA}obi OS 1.0"
for f in /etc/os-release /usr/lib/os-release; do
    [ -f "$f" ] && sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"${PRETTY}\"|" "$f"
done
[ -f /etc/lsb-release ] && sed -i "s|^DISTRIB_DESCRIPTION=.*|DISTRIB_DESCRIPTION=\"${PRETTY}\"|" /etc/lsb-release
systemctl disable aiobi-firstboot-rebrand.service 2>/dev/null || true
EOF
chmod 755 /usr/local/sbin/aiobi-firstboot-rebrand.sh
systemctl enable aiobi-firstboot-rebrand.service 2>/dev/null || \
    ln -sf /etc/systemd/system/aiobi-firstboot-rebrand.service \
           /etc/systemd/system/multi-user.target.wants/aiobi-firstboot-rebrand.service
echo "  first-boot PRETTY_NAME resistance service installed"

echo "==> 05 done — About panel will now read \"$PRETTY\""
echo "    (first-boot service reverts PRETTY_NAME if Cubic overwrote at bake time)"
