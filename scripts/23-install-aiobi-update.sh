#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 23 — Native update mechanism (aiobi-update)
# ----------------------------------------------------------------------------
# Purpose : install the aiobi-update CLI + systemd timers/services/user-path
#           unit that replace Ubuntu's update-manager / update-notifier GUI
#           stack. That stack fails on Aïobi because it depends on
#           apport/whoopsie/ubuntu-report — components aos-debloat.service
#           purges at first boot — and carries no Aïobi branding.
#
# Also purges + pins Ubuntu's native update GUIs (update-manager,
# update-notifier, software-properties-gtk) so aiobi-update is the only
# update surface on the system; software-properties-common is deliberately
# spared (scripts 01 and 12 rely on add-apt-repository).
#
# Source layout
#   The source lives at aiobi-update/ in the parent repository, mirroring
#   the aiobi-term/ layout (first-class files, not heredocs):
#     aiobi-update/aiobi-update              Python 3 launcher (stdlib + gi)
#     aiobi-update/aiobi_update/             Python package (state/policy/apt/
#                                             notify/popup/cli), no deps
#                                             beyond PyGObject family
#     aiobi-update/update.conf               policy config (source for
#                                             /etc/aiobi/update.conf)
#     aiobi-update/systemd/system/*.timer    aiobi-update.timer,
#                                             aiobi-update-security.timer
#     aiobi-update/systemd/system/*.service  aiobi-update.service,
#                                             aiobi-update-apply.service
#     aiobi-update/systemd/user/*            aiobi-update-notify.path,
#                                             aiobi-update-notify.service
#     aiobi-update/apt.conf.d/52-aiobi-update-hooks   DPkg pre/post hooks
#     aiobi-update/logrotate.d/aiobi-update           log rotation
#     aiobi-update/no-ubuntu-updater.pref              APT pin
#
# Install targets
#   /usr/local/bin/aiobi-update                        launcher (0755)
#   /usr/local/lib/aiobi-update/aiobi_update/           package (0644 files)
#   /etc/aiobi/update.conf                              policy config (0644)
#   /etc/systemd/system/aiobi-update.timer|.service     (0644)
#   /etc/systemd/system/aiobi-update-apply.service      (0644)
#   /etc/systemd/system/aiobi-update-security.timer     (0644)
#   /etc/systemd/user/aiobi-update-notify.path|.service (0644)
#   /etc/apt/apt.conf.d/52-aiobi-update-hooks           (0644)
#   /etc/apt/preferences.d/no-ubuntu-updater.pref       (0644)
#   /etc/logrotate.d/aiobi-update                       (0644)
#   /var/lib/aiobi-update/                              state dir (created here)
#   /run/aiobi-update/                                  tmpfs — NOT created
#                                                        here; created at
#                                                        runtime by
#                                                        aiobi-update.service's
#                                                        ExecStartPre
#
# Chroot-safety
#   No systemctl daemon calls beyond `enable` (which only creates symlinks
#   and works without a running systemd); `systemctl enable` falls back to
#   a manual symlink when systemd is not PID 1 (chroot). No `systemctl
#   start` is issued — activation happens at first real boot.
#
# Idempotent: install -m always overwrites; purge commands are no-ops if
# the packages are already absent; pin file and hooks are overwritten
# verbatim on every run.
#
# Ordering: placed between 21-configure-bash-completion.sh and
# 06-apply-persistence.sh (which seals /etc/skel + dconf state) — see
# scripts/run-all.sh for the full rationale and run-all-patch.txt for the
# exact diff.
# ============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi — 23-install-aiobi-update.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$HERE/aiobi-update"
SRC_CLI="$SRC_DIR/aiobi-update"
SRC_PKG="$SRC_DIR/aiobi_update"
SRC_CONF="$SRC_DIR/update.conf"
SRC_SYSTEMD_SYSTEM="$SRC_DIR/systemd/system"
SRC_SYSTEMD_USER="$SRC_DIR/systemd/user"
SRC_APT_HOOK="$SRC_DIR/apt.conf.d/52-aiobi-update-hooks"
SRC_HOOK_SCRIPT="$SRC_DIR/hook.sh"
SRC_LOGROTATE="$SRC_DIR/logrotate.d/aiobi-update"
SRC_PIN="$SRC_DIR/no-ubuntu-updater.pref"

LIB_DIR=/usr/local/lib/aiobi-update

# ----- 1) Sanity check the source files are present -------------------------
[ -f "$SRC_CLI" ]  || { echo "ERROR: $SRC_CLI missing"; exit 2; }
[ -d "$SRC_PKG" ]  || { echo "ERROR: $SRC_PKG package missing"; exit 2; }
[ -f "$SRC_CONF" ] || { echo "ERROR: $SRC_CONF missing"; exit 2; }
[ -d "$SRC_SYSTEMD_SYSTEM" ] || { echo "ERROR: $SRC_SYSTEMD_SYSTEM missing"; exit 2; }
[ -d "$SRC_SYSTEMD_USER" ]   || { echo "ERROR: $SRC_SYSTEMD_USER missing"; exit 2; }
[ -f "$SRC_APT_HOOK" ]     || { echo "ERROR: $SRC_APT_HOOK missing"; exit 2; }
[ -f "$SRC_HOOK_SCRIPT" ]  || { echo "ERROR: $SRC_HOOK_SCRIPT missing"; exit 2; }
[ -f "$SRC_LOGROTATE" ]    || { echo "ERROR: $SRC_LOGROTATE missing"; exit 2; }
[ -f "$SRC_PIN" ]          || { echo "ERROR: $SRC_PIN missing"; exit 2; }

# ----- 2a) DEFENSIVE — repair hook file + helper BEFORE any apt call --------
# If a previous run left a broken /etc/apt/apt.conf.d/52-aiobi-update-hooks
# in place (or if the file references /usr/local/lib/aiobi-update/hook.sh
# which does not yet exist), every subsequent apt-get invocation aborts
# with a parser error, killing this script at step 3 (apt install). Land
# the current hook file + helper script first so the file on disk always
# points at a valid, existing script by the time we touch apt.
install -d -m 0755 "$LIB_DIR"
install -m 0755 "$SRC_HOOK_SCRIPT" "$LIB_DIR/hook.sh"
install -m 0644 "$SRC_APT_HOOK" /etc/apt/apt.conf.d/52-aiobi-update-hooks
echo "  hook file + helper installed early (self-repair against broken prior state)"

# ----- 2b) Purge conflicting Ubuntu native update GUIs ----------------------
# Ubuntu ships update-manager (the "Software Updater" popup) and
# software-properties-gtk (the "Software & Updates" settings panel). Both
# fail on Aïobi because they depend on the apport/whoopsie stack that
# aos-debloat.service removes at first boot, and neither carries the Aïobi
# visual identity. aiobi-update replaces them.
#
# CRITICAL: do NOT purge software-properties-common — it provides
# add-apt-repository which scripts 01 and 12 rely on.
echo "  purging Ubuntu native update GUIs (update-manager, update-notifier, software-properties-gtk)..."
apt-get purge -y \
    update-manager update-manager-core \
    update-notifier update-notifier-common \
    software-properties-gtk \
    2>/dev/null || true
apt-get autoremove --purge -y 2>/dev/null || true

# ----- 3) Runtime dependencies ------------------------------------------------
echo "  installing runtime dependencies..."
apt-get install -y \
    python3-gi \
    gir1.2-gtk-4.0 \
    gir1.2-adw-1 \
    libadwaita-1-0 \
    libnotify-bin

# ----- 4) Directories ---------------------------------------------------------
install -d -m 0755 "$LIB_DIR"
install -d -m 0755 /etc/aiobi
install -d -m 0755 /var/lib/aiobi-update
# /run is tmpfs and does not survive Cubic's chroot capture into the ISO;
# /run/aiobi-update is created at first-boot runtime by
# aiobi-update.service's ExecStartPre (see the unit file), not here.

# ----- 5) Install the CLI launcher + Python package --------------------------
install -m 0755 "$SRC_CLI" /usr/local/bin/aiobi-update
echo "  installed /usr/local/bin/aiobi-update"

rm -rf "$LIB_DIR/aiobi_update"
cp -r "$SRC_PKG" "$LIB_DIR/aiobi_update"
find "$LIB_DIR/aiobi_update" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find "$LIB_DIR/aiobi_update" -type d -exec chmod 0755 {} +
find "$LIB_DIR/aiobi_update" -type f -exec chmod 0644 {} +
echo "  installed $LIB_DIR/aiobi_update ($(find "$LIB_DIR/aiobi_update" -name '*.py' | wc -l) Python files)"

# ----- 6) Policy config --------------------------------------------------------
install -m 0644 "$SRC_CONF" /etc/aiobi/update.conf
echo "  installed /etc/aiobi/update.conf"

# ----- 7) Systemd units --------------------------------------------------------
install -m 0644 "$SRC_SYSTEMD_SYSTEM/aiobi-update.timer" /etc/systemd/system/aiobi-update.timer
install -m 0644 "$SRC_SYSTEMD_SYSTEM/aiobi-update.service" /etc/systemd/system/aiobi-update.service
install -m 0644 "$SRC_SYSTEMD_SYSTEM/aiobi-update-apply.service" /etc/systemd/system/aiobi-update-apply.service
install -m 0644 "$SRC_SYSTEMD_SYSTEM/aiobi-update-security.timer" /etc/systemd/system/aiobi-update-security.timer
echo "  installed system units: aiobi-update.timer, aiobi-update.service, aiobi-update-apply.service, aiobi-update-security.timer"

install -d -m 0755 /etc/systemd/user
install -m 0644 "$SRC_SYSTEMD_USER/aiobi-update-notify.path" /etc/systemd/user/aiobi-update-notify.path
install -m 0644 "$SRC_SYSTEMD_USER/aiobi-update-notify.service" /etc/systemd/user/aiobi-update-notify.service
echo "  installed user units: aiobi-update-notify.path, aiobi-update-notify.service"

# ----- 8) APT hook + hook helper + logrotate + pin -----------------------------
install -m 0644 "$SRC_APT_HOOK" /etc/apt/apt.conf.d/52-aiobi-update-hooks
install -m 0755 "$SRC_HOOK_SCRIPT" "$LIB_DIR/hook.sh"
install -m 0644 "$SRC_LOGROTATE" /etc/logrotate.d/aiobi-update
install -m 0644 "$SRC_PIN" /etc/apt/preferences.d/no-ubuntu-updater.pref
echo "  installed apt hook, hook helper, logrotate config, and no-ubuntu-updater.pref"

# ----- 9) Byte-compile ---------------------------------------------------------
python3 -c "import py_compile; py_compile.compile('/usr/local/bin/aiobi-update', doraise=True)" \
    2>/dev/null || echo "  (CLI byte-compile skipped)"
python3 -m compileall -q "$LIB_DIR/aiobi_update" 2>/dev/null || echo "  (package byte-compile skipped)"

# ----- 10) Enable system timers -------------------------------------------------
# systemctl enable only creates symlinks — it works without a running
# systemd, but the direct symlink fallback covers chroots where even that
# thin call is refused.
for unit in aiobi-update.timer aiobi-update-security.timer; do
    systemctl enable "$unit" 2>/dev/null || \
        ln -sf "/etc/systemd/system/$unit" \
               "/etc/systemd/system/timers.target.wants/$unit"
done
mkdir -p /etc/systemd/system/timers.target.wants 2>/dev/null || true
echo "  enabled aiobi-update.timer + aiobi-update-security.timer"

# aiobi-update-notify.path is a --user unit; it cannot be enabled system-wide
# in a chroot (no logged-in user session exists). It ships to
# /etc/systemd/user/ and is enabled per-user at first login via the
# existing first-boot provisioning path (same pattern as aos-debloat.service
# activates system units at first boot) — Aïobi's session bring-up already
# runs `systemctl --user enable --now aiobi-update-notify.path` there.

# ----- 11) Verification ---------------------------------------------------------
echo
echo "== Verification =="
if head -1 /usr/local/bin/aiobi-update | grep -q python3; then
    echo "  ✓ /usr/local/bin/aiobi-update shebang points at python3"
fi
[ -f /etc/aiobi/update.conf ] && echo "  ✓ /etc/aiobi/update.conf present"
[ -d "$LIB_DIR/aiobi_update" ] && echo "  ✓ $LIB_DIR/aiobi_update present"
[ -f /etc/apt/preferences.d/no-ubuntu-updater.pref ] && echo "  ✓ no-ubuntu-updater.pref present"

if python3 -c "
import sys
sys.path.insert(0, '$LIB_DIR')
from aiobi_update import cli
print(f'  ✓ aiobi_update.cli imports; version {cli.__version__ if hasattr(cli, \"__version__\") else \"?\"}')
" 2>&1; then
    :
else
    echo "  ✗ aiobi_update package import failed — check $LIB_DIR/aiobi_update/ layout"
fi

echo "== apt-cache policy update-manager =="
POLICY_OUT=$(apt-cache policy update-manager 2>&1 || true)
printf '%s\n' "$POLICY_OUT" | sed -n '1,4p'

echo "==> 23 done — aiobi-update installed"
echo "    Try after login:  aiobi-update"
echo "                      aiobi-update --check"
echo "                      aiobi-update --apply"
echo "                      aiobi-update --log"
