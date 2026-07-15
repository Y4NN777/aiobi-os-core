#!/usr/bin/env bash
# =============================================================================
# Test — Step 23 — aiobi-update native update mechanism
# =============================================================================
# Verifies the full aiobi-update layout after scripts/23-install-aiobi-update.sh
# has run: CLI + Python package + config + systemd units + polkit action +
# apply-helper + APT hook + pin file. Also confirms the Ubuntu native update
# GUIs (update-manager, update-notifier, software-properties-gtk) are gone
# and pinned at -10 so they cannot be re-installed.
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 23 — aiobi-update installed and Ubuntu updater purged"

# ----- CLI launcher + Python package ---------------------------------------
CLI=/usr/local/bin/aiobi-update
LIB=/usr/local/lib/aiobi-update
PKG="$LIB/aiobi_update"

assert_executable "$CLI"
if [ -f "$CLI" ] && head -1 "$CLI" | grep -q "python3"; then
    pass "aiobi-update shebang points at python3"
else
    fail "aiobi-update shebang points at python3" "not found"
fi

assert_dir "$PKG"
for mod in __init__ cli state policy apt notify popup; do
    assert_file "$PKG/${mod}.py"
done

# ----- Config + state dir --------------------------------------------------
assert_file /etc/aiobi/update.conf
assert_grep /etc/aiobi/update.conf "[cadence]"
assert_grep /etc/aiobi/update.conf "[blacklist]"
assert_grep /etc/aiobi/update.conf "snapd"

assert_dir /var/lib/aiobi-update

# ----- Systemd units (system) ----------------------------------------------
assert_systemd_unit /etc/systemd/system/aiobi-update.timer
assert_systemd_unit /etc/systemd/system/aiobi-update.service
assert_systemd_unit /etc/systemd/system/aiobi-update-apply.service
assert_systemd_unit /etc/systemd/system/aiobi-update-security.timer

# Timers enabled via symlink in timers.target.wants (chroot-safe assertion —
# does not require systemctl to be running).
if [ -L /etc/systemd/system/timers.target.wants/aiobi-update.timer ] \
   || systemctl is-enabled aiobi-update.timer 2>/dev/null | grep -q enabled; then
    pass "aiobi-update.timer enabled"
else
    fail "aiobi-update.timer enabled" "no symlink and systemctl reports not enabled"
fi
if [ -L /etc/systemd/system/timers.target.wants/aiobi-update-security.timer ] \
   || systemctl is-enabled aiobi-update-security.timer 2>/dev/null | grep -q enabled; then
    pass "aiobi-update-security.timer enabled"
else
    fail "aiobi-update-security.timer enabled" "no symlink and systemctl reports not enabled"
fi

# ----- Systemd units (user) ------------------------------------------------
assert_systemd_unit /etc/systemd/user/aiobi-update-notify.path
assert_systemd_unit /etc/systemd/user/aiobi-update-notify.service

# ----- Polkit action + apply-helper (pkexec target) ------------------------
assert_file /usr/share/polkit-1/actions/com.aiobi.update.policy
assert_grep /usr/share/polkit-1/actions/com.aiobi.update.policy "com.aiobi.update.apply"
assert_grep /usr/share/polkit-1/actions/com.aiobi.update.policy \
    "/usr/local/lib/aiobi-update/apply-helper.sh"

assert_executable "$LIB/apply-helper.sh"

# ----- APT hook + hook helper ----------------------------------------------
assert_file /etc/apt/apt.conf.d/52-aiobi-update-hooks
assert_grep /etc/apt/apt.conf.d/52-aiobi-update-hooks \
    "/usr/local/lib/aiobi-update/hook.sh"
assert_executable "$LIB/hook.sh"

# The hook file must parse cleanly under apt-config — reproduces the bug
# that failed the pipeline mid-install before the hook was delegated to a
# shell script (Extra junk after value at line 14).
if apt-config -c /etc/apt/apt.conf.d/52-aiobi-update-hooks dump 2>/dev/null \
   | grep -q '/usr/local/lib/aiobi-update/hook.sh'; then
    pass "APT hook file parses under apt-config"
else
    fail "APT hook file parses under apt-config" "apt-config dump did not surface the hook line"
fi

# ----- Logrotate + APT pin file --------------------------------------------
assert_file /etc/logrotate.d/aiobi-update

PIN=/etc/apt/preferences.d/no-ubuntu-updater.pref
assert_file "$PIN"
if [ -f "$PIN" ]; then
    for pkg in update-manager update-manager-core update-notifier \
               update-notifier-common software-properties-gtk; do
        if awk -v p="$pkg" '
            /^Package:/ {cur = $2}
            /^Pin-Priority:/ && cur == p && $2 == "-10" {found = 1; exit}
            END {exit found ? 0 : 1}
        ' "$PIN"; then
            pass "APT pin -10 for $pkg present"
        else
            fail "APT pin -10 for $pkg present" "block missing or wrong priority"
        fi
    done
fi

# ----- Ubuntu native update GUIs purged ------------------------------------
assert_no_pkg update-manager
assert_no_pkg update-manager-core
assert_no_pkg update-notifier
assert_no_pkg update-notifier-common
assert_no_pkg software-properties-gtk

# CRITICAL — software-properties-common must remain (scripts 01 + 12 use
# add-apt-repository).
assert_pkg software-properties-common

# ----- Runtime deps for the GTK popup + notif-send -------------------------
assert_pkg python3-gi
assert_pkg gir1.2-gtk-4.0
assert_pkg gir1.2-adw-1
assert_pkg libadwaita-1-0
assert_pkg libnotify-bin

# ----- Package import smoke test --------------------------------------------
if python3 -c "
import sys
sys.path.insert(0, '/usr/local/lib/aiobi-update')
from aiobi_update import cli
sys.exit(0 if hasattr(cli, 'main') else 1)
" 2>/dev/null; then
    pass "aiobi_update.cli imports and exposes main()"
else
    fail "aiobi_update.cli imports and exposes main()" "import or attribute check failed"
fi

finalize
