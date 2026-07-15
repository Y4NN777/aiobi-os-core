#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 15 — Ollama edge-AI daemon + pre-pulled models
# ----------------------------------------------------------------------------
# Purpose : install Ollama as a system service, bind it to the loopback
#           interface only (127.0.0.1), configure it to unload models after
#           an idle window (OLLAMA_KEEP_ALIVE), and pre-pull the two Qwen
#           models the Aïobi AI layer relies on:
#             - qwen2.5:1.5b   (terminal SLM: chat + shell-command extraction
#                              via aiobi-term with two system prompts, ~1 GB)
#             - qwen3-vl:2b-instruct-q8_0
#                              (desktop VLM: multi-modal chat exposed through
#                              AnythingLLM, text + image input, ~2.6 GB — the
#                              Q8 Instruct variant is picked over the Q4 base
#                              tag to eliminate the reasoning-token verbosity
#                              observed on the base tag for vision responses.)
#
# Zero-data-leak posture
#   OLLAMA_HOST=127.0.0.1 tells the daemon to bind exclusively on the
#   loopback interface. No listener is exposed on any external NIC. Any
#   subsequent misconfiguration that would broaden the binding is visible
#   by inspecting the drop-in file installed below.
#
# Memory posture
#   OLLAMA_KEEP_ALIVE=5m unloads model weights from RAM after five minutes
#   of idleness. Combined with the socket-activation configured in
#   16-tune-ram.sh, the daemon converges to zero resident-memory cost
#   when no query has arrived recently.
#
# References
#   - Ollama installation script (upstream): https://ollama.com/install.sh
#   - Ollama environment variables: https://github.com/ollama/ollama/blob/main/docs/faq.md
#
# Idempotent: the upstream install script is idempotent on the daemon;
# the drop-in override is overwritten every run; `ollama pull` is a no-op
# on a model already present.
#
# Ordering: run at any point of the customization pipeline after basic
# apt tooling is available. Recommended late (after 13-productivity-stack)
# so the heavy Qwen model files do not slow earlier layers.
# ============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi — 15-install-ollama.sh"

# ----- 1) Install Ollama via upstream one-liner -----------------------------
if ! command -v ollama >/dev/null 2>&1; then
    echo "  installing Ollama from upstream…"
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "  Ollama already installed: $(ollama --version 2>/dev/null || echo unknown)"
fi

# ----- 2) Drop-in override: loopback + keep-alive ----------------------------
DROPIN_DIR=/etc/systemd/system/ollama.service.d
mkdir -p "$DROPIN_DIR"
tee "$DROPIN_DIR/override.conf" > /dev/null << 'EOF'
# Aïobi OS — Ollama drop-in
# Loopback-only bind (Zero Data Leak posture) + keep-alive 5 min (RAM budget).
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_KEEP_ALIVE=5m"
Environment="OLLAMA_MODELS=/usr/share/ollama/.ollama/models"
EOF
echo "  installed $DROPIN_DIR/override.conf (loopback + keep-alive)"

# Reload systemd so the drop-in takes effect. Inside a chroot this is a no-op.
systemctl daemon-reload 2>/dev/null || true
systemctl restart ollama.service 2>/dev/null || \
    echo "  ollama restart deferred (chroot mode; systemd not managing units here)"

# ----- 3) Pre-pull the Qwen models the AI layer depends on ------------------
# ollama pull writes into $OLLAMA_MODELS, which the drop-in points at
# /usr/share/ollama/.ollama/models (system-wide, mkfs.squashfs-friendly).

MODELS_DIR=/usr/share/ollama/.ollama/models
# `install -d` sets ownership only on the final directory, not on
# intermediates. The Ollama daemon runs as user `ollama` and writes
# an SSH-signing keypair at $HOME/.ollama/id_ed25519 on first start;
# if any parent directory is root-owned it dies with 'permission
# denied' before binding. We chown the full HOME tree explicitly.
mkdir -p "$MODELS_DIR"
chown -R ollama:ollama /usr/share/ollama
chmod -R u+rwX,g+rX,o+rX /usr/share/ollama

# Chroot-time pull strategy (air-gapped install support):
#
#   Aïobi's defense positioning requires models to SHIP IN THE ISO so
#   the on-device AI works out of the box without network access at
#   first login. That means the pull must complete at chroot / build
#   time, not deferred to first boot.
#
#   Two possible paths bind an Ollama daemon at chroot time:
#     - Path A: systemctl restart ollama.service (works when Cubic's
#       chroot has functional systemd — some setups do, some don't)
#     - Path B: manual background `ollama serve` process as a fallback
#       for chroot environments where systemctl cannot bring up units
#
#   We try Path A first (systemctl restart above already fired at the
#   end of section 2). If the daemon is not reachable within 10 s, we
#   fall through to Path B — start the daemon manually in the
#   background, pull, then kill it. On the installed system systemd
#   manages the daemon normally on first boot.
#
#   The `aiobi-ollama-firstpull.service` registered further down remains
#   as a defensive fallback for any edge case where chroot-time pull
#   fails silently — it re-attempts the pull on first boot post-install.
#   With the chroot pull working, `ollama pull` is a no-op on already-
#   present models and the marker file is touched harmlessly.

# Wait for the daemon to be fully bound on 127.0.0.1:11434 before pulling.
wait_for_ollama() {
    local deadline=$(( $(date +%s) + $1 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if curl -sf --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

OLLAMA_PID=""

# Path A: systemctl-managed daemon (already attempted at line above via
# `systemctl restart ollama.service`). Give it 10 s to bind before we
# fall through to the manual start.
if wait_for_ollama 10; then
    echo "  ollama daemon reachable via systemd — pulling at chroot time"
else
    # Path B: manual background daemon (chroot fallback).
    echo "  ollama daemon not reachable via systemd — starting manually in background"
    sudo -u ollama env \
        HOME=/usr/share/ollama \
        OLLAMA_HOST=127.0.0.1:11434 \
        OLLAMA_MODELS=/usr/share/ollama/.ollama/models \
        nohup ollama serve > /tmp/aiobi-ollama-chroot-serve.log 2>&1 &
    OLLAMA_PID=$!
    sleep 2
    if ! wait_for_ollama 30; then
        echo "  ⚠ ollama daemon did not bind within 30 s at chroot time"
        echo "  → check /tmp/aiobi-ollama-chroot-serve.log"
        echo "  → models will be pulled by aiobi-ollama-firstpull.service on first boot instead"
    fi
fi

# If any daemon (Path A or B) is now bound, pull the two models.
CHROOT_PULL_OK=0
if curl -sf --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    PULL_FAILED=0
    sudo -u ollama env HOME=/usr/share/ollama ollama pull qwen2.5:1.5b \
        || { echo "    ⚠ qwen2.5:1.5b pull failed"; PULL_FAILED=1; }
    sudo -u ollama env HOME=/usr/share/ollama ollama pull qwen3-vl:2b-instruct-q8_0 \
        || { echo "    ⚠ qwen3-vl:2b-instruct-q8_0 pull failed"; PULL_FAILED=1; }
    if [ "$PULL_FAILED" -eq 0 ]; then
        CHROOT_PULL_OK=1
        echo "  models baked in at $(du -sh /usr/share/ollama/.ollama/models 2>/dev/null | cut -f1)"

        # Touch the marker file so aiobi-ollama-firstpull.service skips on
        # the installed system — chroot pull already covered both models,
        # firstpull becomes truly a fallback that only activates on the
        # edge case where chroot pull failed silently.
        mkdir -p /var/lib
        touch /var/lib/aiobi-ollama-firstpull-done
        echo "  marker /var/lib/aiobi-ollama-firstpull-done touched — firstpull will skip on installed system"
    fi
fi

# Clean up the manual background daemon (systemd manages the real one on
# the installed system). No-op if Path A was used.
if [ -n "$OLLAMA_PID" ]; then
    kill "$OLLAMA_PID" 2>/dev/null || true
    wait "$OLLAMA_PID" 2>/dev/null || true
fi

# --- Defensive first-boot fallback service --------------------------------
# Always register the firstpull service — belt-and-suspenders for the
# edge case where the chroot-time pull above failed silently. Uses an
# absolute, filesystem-verified path (fix for the Jul 14 boot failure
# where the service died with status=203/EXEC due to $OLLAMA_BIN
# resolving to an empty or non-existent path).
if [ -x /usr/local/bin/ollama ]; then
    OLLAMA_BIN=/usr/local/bin/ollama
elif [ -x /usr/bin/ollama ]; then
    OLLAMA_BIN=/usr/bin/ollama
else
    # Should never reach here — the upstream installer places the binary
    # at /usr/local/bin/ollama. Fall through with best-effort default.
    OLLAMA_BIN=/usr/local/bin/ollama
    echo "  ⚠ ollama binary not found at expected paths — firstpull service may fail with 203/EXEC"
fi

tee /etc/systemd/system/aiobi-ollama-firstpull.service > /dev/null <<EOF
[Unit]
Description=Aïobi OS — pull Qwen models on first boot (defensive fallback)
Requires=network-online.target ollama.service
After=network-online.target ollama.service
ConditionPathExists=!/var/lib/aiobi-ollama-firstpull-done

[Service]
Type=oneshot
User=ollama
Environment=HOME=/usr/share/ollama
Environment=OLLAMA_HOST=http://127.0.0.1:11435
ExecStartPre=/bin/sh -c 'until curl -sf http://127.0.0.1:11435/api/tags >/dev/null 2>&1; do sleep 1; done'
ExecStart=${OLLAMA_BIN} pull qwen2.5:1.5b
ExecStart=${OLLAMA_BIN} pull qwen3-vl:2b-instruct-q8_0
ExecStartPost=/usr/bin/touch /var/lib/aiobi-ollama-firstpull-done
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable aiobi-ollama-firstpull.service 2>/dev/null || \
    ln -sf /etc/systemd/system/aiobi-ollama-firstpull.service \
           /etc/systemd/system/multi-user.target.wants/aiobi-ollama-firstpull.service

echo "  firstpull fallback service registered (activates only if models are absent at first boot)"

# ----- 4) Verification --------------------------------------------------------
echo
echo "== Verification =="
echo "  drop-in:      $(ls "$DROPIN_DIR/override.conf" 2>/dev/null && echo present || echo MISSING)"
echo "  daemon:       $(systemctl is-active ollama.service 2>/dev/null || echo not-running)"
echo "  bind (proc):  $(ss -tln 2>/dev/null | grep ':11434 ' || echo not-listening)"
echo "  models dir:   $(ls -la "$MODELS_DIR" 2>/dev/null | head -3 || echo empty-or-missing)"

echo "==> 15 done — Ollama installed, loopback-bound, keep-alive 5m, models pre-registered"
