#!/usr/bin/env bash
# =============================================================================
# Test — Step 20 — AI zero-data-leak firewall
# =============================================================================
# Verifies that the iptables/ip6tables rule files carry the expected
# ACCEPT-loopback + REJECT-everything-else pair for TCP dport 11434, so
# a local AI client can only reach the loopback Ollama endpoint.
# When the harness runs on a live systemd host, packet counters for the
# rules are printed for informational context (not asserted).
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 20 — 11434 outbound blocked off loopback (v4 + v6)"

V4=/etc/iptables/rules.v4
V6=/etc/iptables/rules.v6

# ----- IPv4 -----------------------------------------------------------------
assert_file "$V4"
if [ -f "$V4" ]; then
    # Accept on loopback range.
    if grep -qE '^-A OUTPUT -p tcp --dport 11434 -d 127\.0\.0\.0/8 -j ACCEPT' "$V4"; then
        pass "IPv4 rule: OUTPUT ACCEPT loopback dport 11434"
    else
        fail "IPv4 rule: OUTPUT ACCEPT loopback dport 11434" "not found"
    fi
    # Reject everywhere else.
    if grep -qE '^-A OUTPUT -p tcp --dport 11434 -j REJECT' "$V4"; then
        pass "IPv4 rule: OUTPUT REJECT dport 11434 (non-loopback)"
    else
        fail "IPv4 rule: OUTPUT REJECT dport 11434 (non-loopback)" "not found"
    fi
fi

# ----- IPv6 -----------------------------------------------------------------
assert_file "$V6"
if [ -f "$V6" ]; then
    if grep -qE '^-A OUTPUT -p tcp --dport 11434 -d ::1/128 -j ACCEPT' "$V6"; then
        pass "IPv6 rule: OUTPUT ACCEPT ::1 dport 11434"
    else
        fail "IPv6 rule: OUTPUT ACCEPT ::1 dport 11434" "not found"
    fi
    if grep -qE '^-A OUTPUT -p tcp --dport 11434 -j REJECT' "$V6"; then
        pass "IPv6 rule: OUTPUT REJECT dport 11434 (non-::1)"
    else
        fail "IPv6 rule: OUTPUT REJECT dport 11434 (non-::1)" "not found"
    fi
fi

# ----- Runtime informational context ----------------------------------------
# Live host: dump packet counters for the OUTPUT dport 11434 rules so a
# curious operator can see whether the guard has actually been exercised.
# Purely informational — NOT asserted.
if have_systemd && command -v iptables >/dev/null 2>&1; then
    counters=$(iptables -L OUTPUT -v -n 2>/dev/null | grep -E 'dpt:11434' || true)
    if [ -n "$counters" ]; then
        printf '  info  iptables OUTPUT counters (dpt:11434):\n'
        printf '%s\n' "$counters" | sed 's/^/          /'
    fi
fi

finalize
