#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 15 — Ollama edge-AI daemon + pre-pulled models
# ----------------------------------------------------------------------------
# Purpose : install Ollama as a system service, bind it to the loopback
#           interface only (127.0.0.1), configure it to unload models after
#           an idle window (OLLAMA_KEEP_ALIVE), and pre-pull the two Qwen 2.5
#           models the Aïobi AI layer relies on:
#             - qwen2.5:1.5b        (general-purpose chat, ~1 GB)
#             - qwen2.5-coder:0.5b  (natural-language → shell command, ~400 MB)
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
install -d -o ollama -g ollama -m 0755 "$MODELS_DIR" 2>/dev/null || \
    mkdir -p "$MODELS_DIR"

# On a live system: pull via the running daemon.
# In a chroot (no live daemon): the pull is deferred to first boot via the
# firstboot service registered below. We detect the mode via `systemctl
# is-active`.

# Wait for the daemon to be fully bound on 127.0.0.1:11434 before pulling.
# systemctl is-active returns success on both "active" and "activating";
# the API endpoint being reachable is the only reliable readiness signal.
wait_for_ollama() {
    local deadline=$(( $(date +%s) + 60 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if curl -sf --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

if systemctl is-active --quiet ollama.service 2>/dev/null && wait_for_ollama; then
    echo "  daemon is ready — pulling models now"
    sudo -u ollama env HOME=/usr/share/ollama ollama pull qwen2.5:1.5b       || echo "    ⚠ qwen2.5:1.5b pull failed"
    sudo -u ollama env HOME=/usr/share/ollama ollama pull qwen2.5-coder:0.5b || echo "    ⚠ qwen2.5-coder:0.5b pull failed"
elif systemctl is-active --quiet ollama.service 2>/dev/null; then
    echo "  daemon is active but did not become reachable within 60s"
    echo "  → re-run this script or invoke 'ollama pull qwen2.5:1.5b' manually once the daemon is ready"
else
    echo "  daemon not active (chroot mode) — registering first-boot pull service"

    # Deferred pull via a one-shot systemd service run on first boot.
    tee /etc/systemd/system/aiobi-ollama-firstpull.service > /dev/null << 'EOF'
[Unit]
Description=Aïobi OS — pull Qwen 2.5 models on first boot
Requires=network-online.target ollama.service
After=network-online.target ollama.service
ConditionPathExists=!/var/lib/aiobi-ollama-firstpull-done

[Service]
Type=oneshot
User=ollama
Environment=HOME=/usr/share/ollama
ExecStart=/usr/bin/ollama pull qwen2.5:1.5b
ExecStart=/usr/bin/ollama pull qwen2.5-coder:0.5b
ExecStartPost=/usr/bin/touch /var/lib/aiobi-ollama-firstpull-done
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable aiobi-ollama-firstpull.service 2>/dev/null || \
        ln -sf /etc/systemd/system/aiobi-ollama-firstpull.service \
               /etc/systemd/system/multi-user.target.wants/aiobi-ollama-firstpull.service

    echo "  first-boot pull service enabled"
fi

# ----- 4) Verification --------------------------------------------------------
echo
echo "== Verification =="
echo "  drop-in:      $(ls "$DROPIN_DIR/override.conf" 2>/dev/null && echo present || echo MISSING)"
echo "  daemon:       $(systemctl is-active ollama.service 2>/dev/null || echo not-running)"
echo "  bind (proc):  $(ss -tln 2>/dev/null | grep ':11434 ' || echo not-listening)"
echo "  models dir:   $(ls -la "$MODELS_DIR" 2>/dev/null | head -3 || echo empty-or-missing)"

echo "==> 15 done — Ollama installed, loopback-bound, keep-alive 5m, models pre-registered"
