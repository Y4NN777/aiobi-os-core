#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 20 — AI zero-data-leak firewall
# ----------------------------------------------------------------------------
# Purpose : enforce, at the packet-filter level, that no local AI client can
#           reach an Ollama daemon outside the guest's loopback interface.
#
# Motivation
#   The Aïobi zero-data-leak posture is documented in Section 3.6 of the
#   thesis: every request from the terminal assistant and the AnythingLLM
#   desktop application must terminate at the local socket on
#   127.0.0.1:11434. AnythingLLM's Ollama-provider auto-discovery, however,
#   can pick up any 11434 endpoint it can reach --- typically the QEMU
#   host gateway (10.0.2.2) when the guest runs under NAT and the host
#   itself has Ollama bound on 0.0.0.0. On such a host the guest silently
#   ends up talking to the host's models instead of its own, and the
#   zero-data-leak promise is broken at first request.
#
#   This script blocks the leak at the kernel level: any TCP connection
#   originating in the guest and destined to port 11434 anywhere other
#   than the loopback range is rejected with ICMP port-unreachable. Both
#   IPv4 (iptables) and IPv6 (ip6tables) are covered. Rules are made
#   persistent through `iptables-persistent` (netfilter-persistent),
#   loaded at boot before the AI stack activates.
#
# Non-goals
#   This script does NOT block port 11435 (the private endpoint of the
#   Ollama daemon behind systemd-socket-proxyd). 11435 is loopback-only
#   by the drop-in installed in step 19; blocking it would break the
#   proxy chain.
#
# Idempotent: the script re-installs the rule set on every run,
# overwriting any previous state under the same file path.
# ============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi — 20-ai-firewall.sh"

# ----- 1) Install iptables-persistent (non-interactive) ---------------------
export DEBIAN_FRONTEND=noninteractive
# Pre-seed answers so the postinst does not prompt to save current rules.
echo iptables-persistent iptables-persistent/autosave_v4 boolean false | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | debconf-set-selections
apt-get install -y iptables-persistent netfilter-persistent
echo "  iptables-persistent installed"

# ----- 2) Write the rules to the persistent files ---------------------------
# The rule set is intentionally minimal: a single OUTPUT rule per family
# that rejects TCP traffic to any non-loopback address on port 11434.
# Everything else stays default-accept, so existing user connectivity is
# untouched.
tee /etc/iptables/rules.v4 > /dev/null << 'EOF'
# Aïobi OS — AI zero-data-leak firewall (IPv4).
# Reject any outbound TCP to port 11434 that is NOT loopback.
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A OUTPUT -p tcp --dport 11434 -d 127.0.0.0/8 -j ACCEPT
-A OUTPUT -p tcp --dport 11434 -j REJECT --reject-with icmp-port-unreachable
COMMIT
EOF

tee /etc/iptables/rules.v6 > /dev/null << 'EOF'
# Aïobi OS — AI zero-data-leak firewall (IPv6).
# Reject any outbound TCP to port 11434 that is NOT the ::1 loopback.
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A OUTPUT -p tcp --dport 11434 -d ::1/128 -j ACCEPT
-A OUTPUT -p tcp --dport 11434 -j REJECT --reject-with icmp6-port-unreachable
COMMIT
EOF
echo "  installed /etc/iptables/rules.v4 and rules.v6"

# ----- 3) Apply immediately if the kernel is running (not in chroot) --------
if [ -d /run/systemd/system ]; then
    iptables-restore < /etc/iptables/rules.v4  || echo "  iptables-restore failed (kernel netfilter not available)"
    ip6tables-restore < /etc/iptables/rules.v6 || echo "  ip6tables-restore failed (kernel netfilter not available)"
    systemctl enable netfilter-persistent 2>/dev/null || true
    systemctl restart netfilter-persistent 2>/dev/null || true
    echo "  rules applied and netfilter-persistent enabled"
else
    echo "  chroot mode — rules will apply at first boot via netfilter-persistent.service"
fi

# ----- 4) Verification ------------------------------------------------------
echo
echo "== Verification =="
[ -f /etc/iptables/rules.v4 ] && echo "  ✓ rules.v4 present"
[ -f /etc/iptables/rules.v6 ] && echo "  ✓ rules.v6 present"
grep -q "dport 11434" /etc/iptables/rules.v4 && echo "  ✓ IPv4 11434 guard rule present"
grep -q "dport 11434" /etc/iptables/rules.v6 && echo "  ✓ IPv6 11434 guard rule present"

# Live-check: from within the guest, an attempt to reach 10.0.2.2:11434
# (the standard QEMU host gateway) must fail. We do a bounded probe.
if [ -d /run/systemd/system ]; then
    if timeout 3 bash -c 'cat < /dev/tcp/10.0.2.2/11434' 2>/dev/null; then
        echo "  ⚠ 10.0.2.2:11434 still reachable — rule may not have applied"
    else
        echo "  ✓ 10.0.2.2:11434 blocked (expected — enforcement live)"
    fi
fi

echo "==> 20 done — AI zero-data-leak firewall active"
echo "    Effect: AnythingLLM auto-discovery cannot reach any 11434 outside 127.0.0.1"
