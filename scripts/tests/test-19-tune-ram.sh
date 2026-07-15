#!/usr/bin/env bash
# =============================================================================
# Test — Step 19 — RAM tuning (zRAM + socket-activated Ollama)
# =============================================================================
# Verifies that:
#   - the zram-generator configuration file is installed
#   - the ollama-proxy.socket unit exists and listens on 127.0.0.1:11434
#   - the ollama-proxy.service unit exists, invokes systemd-socket-proxyd
#     against 127.0.0.1:11435 with --exit-idle-time=300, and defines an
#     ExecStartPre wait-loop against the private endpoint
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 19 — zRAM + socket-activated Ollama"

# 1. zRAM configuration file present.
assert_file /etc/systemd/zram-generator.conf

# 2. Ollama proxy socket unit.
SOCKET=/etc/systemd/system/ollama-proxy.socket
assert_systemd_unit "$SOCKET"
if [ -f "$SOCKET" ]; then
    assert_grep "$SOCKET" "ListenStream=127.0.0.1:11434"
fi

# 3. Ollama proxy service unit — key body clauses.
SERVICE=/etc/systemd/system/ollama-proxy.service
assert_systemd_unit "$SERVICE"
if [ -f "$SERVICE" ]; then
    # systemd-socket-proxyd invocation with --exit-idle-time=300 against
    # the private 11435 endpoint.
    if grep -qE 'ExecStart=.*systemd-socket-proxyd.*--exit-idle-time=300.*127\.0\.0\.1:11435' "$SERVICE"; then
        pass "ExecStart uses systemd-socket-proxyd --exit-idle-time=300 → 127.0.0.1:11435"
    else
        fail "ExecStart uses systemd-socket-proxyd --exit-idle-time=300 → 127.0.0.1:11435" \
             "no matching ExecStart line"
    fi

    # ExecStartPre wait-loop against the private endpoint so the proxy
    # never races the daemon.
    if grep -qE 'ExecStartPre=.*11435.*api/tags' "$SERVICE"; then
        pass "ExecStartPre waits on 127.0.0.1:11435 before starting the proxy"
    else
        fail "ExecStartPre waits on 127.0.0.1:11435 before starting the proxy" \
             "no matching ExecStartPre line"
    fi
fi

finalize
