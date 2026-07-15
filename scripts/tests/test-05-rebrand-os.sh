#!/usr/bin/env bash
# =============================================================================
# Test — Step 05 — OS identity rebrand
# =============================================================================
# Verifies that every user-visible identity surface carries the Aïobi
# PRETTY_NAME, that the first-boot resilience service is in place (Cubic
# overwrite recovery), that GRUB references the Aïobi distributor, that
# the MOTD has been rewritten, and that the GNOME initial-setup welcome
# popup is suppressed.
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 05 — OS identity rebranded to Aïobi OS"

# The literal ï byte-sequence — reconstructed here so grep works regardless
# of the invoking shell locale.
PROBE="A$(printf '\xc3\xaf')obi"
PRETTY_PROBE="A$(printf '\xc3\xaf')obi OS 1.0"

check_pretty_in() {
    local f="$1"
    if [ ! -f "$f" ]; then
        fail "PRETTY_NAME in $f" "file missing"
        return
    fi
    if grep -q "^PRETTY_NAME=.*${PRETTY_PROBE}" "$f"; then
        pass "PRETTY_NAME in $f = ${PRETTY_PROBE}"
    else
        fail "PRETTY_NAME in $f = ${PRETTY_PROBE}" "value not present"
    fi
}

check_pretty_in /etc/os-release
check_pretty_in /usr/lib/os-release

# /etc/lsb-release stores its display string as DISTRIB_DESCRIPTION, but
# Cubic overwrites this file at ISO bake time — accept either the value
# being live OR the first-boot resilience service being present to
# restore it. The resilience service is verified below regardless.
if [ -f /etc/lsb-release ] \
   && grep -qE "^DISTRIB_DESCRIPTION=\"?${PRETTY_PROBE}" /etc/lsb-release; then
    pass "DISTRIB_DESCRIPTION in /etc/lsb-release = ${PRETTY_PROBE}"
elif [ -f /etc/systemd/system/aiobi-firstboot-rebrand.service ]; then
    skip "DISTRIB_DESCRIPTION in /etc/lsb-release = ${PRETTY_PROBE}" \
         "Cubic overwrote at bake; first-boot service will restore"
else
    fail "DISTRIB_DESCRIPTION in /etc/lsb-release = ${PRETTY_PROBE}" \
         "value missing and no first-boot resilience service"
fi

# First-boot resilience unit + helper script.
assert_systemd_unit /etc/systemd/system/aiobi-firstboot-rebrand.service
assert_file /usr/local/sbin/aiobi-firstboot-rebrand.sh

# GRUB references Aïobi.
if [ -f /etc/default/grub ]; then
    if grep -qE "^GRUB_DISTRIBUTOR=.*${PROBE}" /etc/default/grub; then
        pass "GRUB_DISTRIBUTOR references Aïobi"
    else
        fail "GRUB_DISTRIBUTOR references Aïobi" "not set"
    fi
else
    skip "GRUB_DISTRIBUTOR references Aïobi" "/etc/default/grub missing"
fi

# MOTD debloated — Aïobi header script installed.
assert_file /etc/update-motd.d/00-aiobi-header

# GNOME initial-setup welcome popup hidden.
GIS_WELCOME=/etc/xdg/autostart/gnome-initial-setup-first-login.desktop
if [ -f "$GIS_WELCOME" ]; then
    assert_grep "$GIS_WELCOME" "Hidden=true"
else
    skip "gnome-initial-setup welcome hidden" "$GIS_WELCOME not present on this base"
fi

finalize
