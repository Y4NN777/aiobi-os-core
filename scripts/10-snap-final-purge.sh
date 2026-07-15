#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 10 — Snap final purge + APT pin
# ----------------------------------------------------------------------------
# Purpose : (a) purge residual snap data left in ~/snap after the base debloat
#           and the first-boot provisioning service have run;
#           (b) install /etc/apt/preferences.d/nosnap.pref with
#           Pin-Priority: -10 to block any future apt install pulling snapd
#           back in as a dependency.
#
# References
#   - Ubuntu MATE community guide on snap block:
#     https://ubuntu-mate.community/t/completely-remove-snap-and-prevent-it-from-ever-installing/28456
#
# Idempotent: rm -rf on ~/snap is safe; tee overwrites nosnap.pref;
# verification via apt-cache policy is idempotent.
#
# Ordering: standalone. Recommended late in the customization pipeline so it
# does not interfere with any snap-based install steps that may have been
# needed earlier in the build (Subiquity in older Ubuntu; not the case on
# 24.04).
# ============================================================================

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Must run as root (sudo)."; exit 1; }

RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

# --- 1. Purge user home residues ---------------------------------------------
# The base debloat step plus the first-boot aos-debloat.service remove snapd
# system-side, but per-user ~/snap/snapd-desktop-integration/ may remain as
# an empty directory.
if [[ -n "$RUN_USER" && "$RUN_USER" != "root" ]]; then
    USER_HOME=$(getent passwd "$RUN_USER" | cut -d: -f6)
    if [[ -d "${USER_HOME}/snap" ]]; then
        rm -rf "${USER_HOME}/snap"
        echo "  removed ${USER_HOME}/snap residue"
    fi
fi
# Also root's if any
[[ -d /root/snap ]] && rm -rf /root/snap

# Live-CD squashfs residue. The vanilla Ubuntu 24.04 live session runs
# snapd as the `ubuntu` user, which populates
# /home/ubuntu/snap/snapd-desktop-integration/ with a full runtime tree
# (font caches, GTK immodules, GIO modules). When Cubic captures the
# live squashfs, that tree is packed into the ISO and Subiquity replicates
# it into every freshly-created user home on install — visible on the
# installed system as `~/snap/snapd-desktop-integration/` even though
# no snapd process ever ran there.
#
# In a chroot the `ubuntu` user home may still be present; glob-purge
# everything under /home/*/snap AND remove the OEM live-CD user home
# entirely. Also purge /etc/skel/snap in case a future Ubuntu base image
# adds a skel stub for it.
rm -rf /home/*/snap 2>/dev/null || true
rm -rf /home/ubuntu 2>/dev/null || true
rm -rf /etc/skel/snap 2>/dev/null || true

# --- 2. APT pin — refuse snapd reinstall via dependency chain ----------------
tee /etc/apt/preferences.d/nosnap.pref > /dev/null << 'EOF'
# Aïobi OS — block snapd reinstallation via dependency chain.
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF
chmod 644 /etc/apt/preferences.d/nosnap.pref

# --- 3. Also pin the snap-related meta packages that could pull snapd back ---
tee -a /etc/apt/preferences.d/nosnap.pref > /dev/null << 'EOF'

Package: snap-confine
Pin: release a=*
Pin-Priority: -10

Package: snapd-desktop-integration
Pin: release a=*
Pin-Priority: -10
EOF

# --- 4. First-boot debloat service — actually purge snapd + companions ------
# Snapd is deliberately KEPT in the ISO because Subiquity (the Ubuntu 24.04
# installer) is a snap; purging it at chroot time would kill installation.
# Instead we ship /usr/local/sbin/aos-debloat.sh + aos-debloat.service that
# run once at first boot POST-INSTALL to purge snapd and its telemetry
# companions, then self-destruct. Live-CD guard via `df -T /` overlay check
# (hardware-level, per CLAUDE.md — casper cmdline check is unreliable on
# 24.04 and only used as fallback). Spec sourced from Log 1 §2.4-§2.5.

tee /usr/local/sbin/aos-debloat.sh > /dev/null << 'EOF'
#!/bin/bash
# Aïobi OS — First-boot debloat (self-destructing oneshot).
# Purges snapd + telemetry companions on the INSTALLED system only.
# Runs once post-install via aos-debloat.service, then removes itself.

# 1. Live-CD guard (hardware-level primary + cmdline fallback)
if df -T / | awk '{print $2}' | grep -q "^overlay$"; then
    exit 0
fi
if grep -q "casper" /proc/cmdline; then
    exit 0
fi

# 2. Wait for post-boot APT locks to release (unattended-upgrades, etc.)
sleep 45

# 3. Purge snapd + telemetry companions
apt-get purge -y snapd ubuntu-report popularity-contest apport whoopsie apport-symptoms
apt-get autoremove --purge -y
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd

# 4. Hold to prevent any dependency chain from reinstalling them
apt-mark hold snapd ubuntu-report popularity-contest apport whoopsie apport-symptoms

# 5. Self-destruct — disable unit, unlink unit + script
systemctl disable aos-debloat.service 2>/dev/null || true
rm -f /etc/systemd/system/aos-debloat.service
rm -f /etc/systemd/system/multi-user.target.wants/aos-debloat.service
rm -f /usr/local/sbin/aos-debloat.sh
EOF
chmod 755 /usr/local/sbin/aos-debloat.sh

tee /etc/systemd/system/aos-debloat.service > /dev/null << 'EOF'
[Unit]
Description=Aïobi OS — first-boot debloat (snapd + telemetry companions)
After=network-online.target
Wants=network-online.target
ConditionPathExists=/usr/local/sbin/aos-debloat.sh

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/aos-debloat.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable — systemctl works when systemd is running, symlink fallback for chroot
systemctl enable aos-debloat.service 2>/dev/null || \
    ln -sf /etc/systemd/system/aos-debloat.service \
           /etc/systemd/system/multi-user.target.wants/aos-debloat.service
echo "  aos-debloat.service enabled (first-boot snapd + telemetry purge)"

# --- 5. Purge stale apt cache so the new pin takes effect immediately -------
apt-get update -qq || true

# --- 6. Verification (chroot expects snapd still installed — purge is deferred
#        to first boot via aos-debloat.service; verify pin + service presence) -
echo "== Verification =="
echo "== apt-cache policy snapd =="
# Capture into a variable first so head does not close the pipe and send
# SIGPIPE upstream (would make pipefail exit 141 kill the pipeline).
POLICY_OUT=$(apt-cache policy snapd 2>&1 || true)
printf '%s\n' "$POLICY_OUT" | sed -n '1,6p'
echo
echo "== residual /snap /var/snap /var/cache/snapd =="
for d in /snap /var/snap /var/cache/snapd; do
    if [[ -e "$d" ]]; then
        echo "  ⚠ $d STILL EXISTS — earlier debloat may be incomplete"
    else
        echo "  ✓ $d absent"
    fi
done
echo
echo "== residual ~/snap =="
if [[ -n "$RUN_USER" && "$RUN_USER" != "root" ]]; then
    if [[ -d "${USER_HOME}/snap" ]]; then
        echo "  ⚠ ${USER_HOME}/snap STILL EXISTS"
    else
        echo "  ✓ ${USER_HOME}/snap absent"
    fi
fi

echo "== 10-snap-final-purge.sh done =="
echo "Effect: any future 'apt install <pkg>' with snapd as a dependency will now be refused."
