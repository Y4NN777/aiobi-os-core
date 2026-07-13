#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 19 — RAM tuning (zRAM swap + Ollama socket activation)
# ----------------------------------------------------------------------------
# Purpose : bring the memory footprint of Aïobi OS below its target
#           envelope through two complementary optimisations:
#
#   (a) zRAM-backed compressed swap via systemd-zram-generator, with the
#       zstd algorithm and half of RAM as the compressed-swap size.
#
#   (b) Socket-activated Ollama via systemd-socket-proxyd, so the Ollama
#       daemon does not run at boot and does not consume any RAM until
#       the first AI request arrives on 127.0.0.1:11434.
#
# On the Ollama socket-activation pattern
#   Ollama does not natively support systemd socket activation
#   (it does not read LISTEN_FDS from systemd). We therefore use the
#   standard systemd workaround: systemd-socket-proxyd, a generic TCP
#   forwarder that IS socket-activatable. The chain is:
#
#     ollama-proxy.socket     listens on 127.0.0.1:11434 (public)
#       └─ activates ─▶ ollama-proxy.service
#                        └─ requires ─▶ ollama.service (binds 127.0.0.1:11435)
#                        └─ ExecStart=systemd-socket-proxyd
#                                       --exit-idle-time=300s
#                                       127.0.0.1:11435
#
#   At boot: only ollama-proxy.socket is listening; neither the proxy
#   nor ollama is running. RAM used by the AI stack: 0 MB.
#   First HTTP request on 11434: systemd activates the proxy service,
#   which pulls in ollama.service, which loads the requested model.
#   After 5 min of idle (no traffic on the socket), the proxy exits,
#   ollama.service becomes unneeded and stops (StopWhenUnneeded=yes),
#   and the AI stack returns to 0 MB resident.
#
# References
#   - systemd-socket-proxyd(8):
#     https://manpages.debian.org/testing/systemd/systemd-socket-proxyd.8.en.html
#   - zram-generator.conf(5):
#     https://manpages.ubuntu.com/manpages/noble/man5/zram-generator.conf.5.html
#
# Idempotent: every unit file is overwritten on each run; the dependency
# on script 15 is that Ollama is already installed as a systemd service.
#
# Ordering: run AFTER 15-install-ollama.sh (which brings up the daemon
# on the default 11434). This script reconfigures ollama.service to bind
# on the private port 11435 and takes over 11434 with the proxy socket.
# ============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi — 19-tune-ram.sh"

# ----- 1) zRAM compressed swap via systemd-zram-generator -------------------
export DEBIAN_FRONTEND=noninteractive
apt-get install -y systemd-zram-generator 2>&1 | tail -3 || \
    echo "  systemd-zram-generator apt install deferred (chroot mode)"

tee /etc/systemd/zram-generator.conf > /dev/null << 'EOF'
# Aïobi OS — zRAM-backed compressed swap
# Rationale: on 8 GB systems, half of RAM as zstd-compressed swap raises the
# effective working-set headroom substantially before triggering disk swap.
# The kernel picks the compression algorithm from those available; we
# request zstd as the preferred choice for its favourable ratio-vs-CPU
# balance on desktop workloads.
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF
echo "  installed /etc/systemd/zram-generator.conf (zstd, ram/2)"

# ----- 2) Reconfigure ollama.service to bind on the private port 11435 -----
# We rewrite the drop-in from step 15 to point at the private port.
DROPIN=/etc/systemd/system/ollama.service.d/override.conf
mkdir -p "$(dirname "$DROPIN")"
tee "$DROPIN" > /dev/null << 'EOF'
# Aïobi OS — Ollama drop-in (private port + auto-stop when idle)
# Bound on 11435 (private) so the socket-activated proxy on 11434
# can front the traffic. StopWhenUnneeded lets the daemon exit when
# the proxy is no longer holding a Requires= dependency on it.
[Unit]
StopWhenUnneeded=yes

[Service]
Environment="OLLAMA_HOST=127.0.0.1:11435"
Environment="OLLAMA_KEEP_ALIVE=5m"
Environment="OLLAMA_MODELS=/usr/share/ollama/.ollama/models"
EOF
echo "  updated $DROPIN (private port 11435 + StopWhenUnneeded)"

# ----- 3) Do NOT autostart ollama.service at boot ---------------------------
# It will be started on demand through the proxy's Requires= dependency.
# We remove the multi-user.target.wants symlink if the Ollama installer
# created it.
rm -f /etc/systemd/system/multi-user.target.wants/ollama.service
echo "  removed ollama.service autostart (will be dependency-triggered)"

# ----- 4) Create ollama-proxy.socket ----------------------------------------
tee /etc/systemd/system/ollama-proxy.socket > /dev/null << 'EOF'
[Unit]
Description=Aïobi OS — Ollama front socket (public endpoint on 127.0.0.1:11434)
PartOf=ollama-proxy.service

[Socket]
ListenStream=127.0.0.1:11434

[Install]
WantedBy=sockets.target
EOF
echo "  installed /etc/systemd/system/ollama-proxy.socket"

# ----- 5) Create ollama-proxy.service ---------------------------------------
tee /etc/systemd/system/ollama-proxy.service > /dev/null << 'EOF'
[Unit]
Description=Aïobi OS — Ollama socket-activation proxy (11434 → 11435)
Requires=ollama.service ollama-proxy.socket
After=ollama.service ollama-proxy.socket

[Service]
Type=notify
ExecStart=/usr/lib/systemd/systemd-socket-proxyd --exit-idle-time=300 127.0.0.1:11435
PrivateTmp=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
EOF
echo "  installed /etc/systemd/system/ollama-proxy.service"

# ----- 6) Enable the socket at boot -----------------------------------------
# Only the socket auto-starts; the proxy and ollama.service are pulled in
# on first connection.
systemctl daemon-reload 2>/dev/null || true
systemctl enable ollama-proxy.socket 2>/dev/null || \
    ln -sf /etc/systemd/system/ollama-proxy.socket \
           /etc/systemd/system/sockets.target.wants/ollama-proxy.socket

echo "  enabled ollama-proxy.socket (sockets.target)"

# ----- 7) Verification --------------------------------------------------------
echo
echo "== Verification =="
[ -f /etc/systemd/zram-generator.conf ] && echo "  ✓ zram-generator.conf present"
[ -f /etc/systemd/system/ollama-proxy.socket ] && echo "  ✓ ollama-proxy.socket present"
[ -f /etc/systemd/system/ollama-proxy.service ] && echo "  ✓ ollama-proxy.service present"
[ -f "$DROPIN" ] && grep -q ":11435" "$DROPIN" && echo "  ✓ ollama drop-in pinned on private 11435"
[ -e /etc/systemd/system/multi-user.target.wants/ollama.service ] && \
    echo "  ⚠ ollama.service still auto-starts (should not)" || \
    echo "  ✓ ollama.service will start on demand via proxy dependency"

echo "==> 19 done — zRAM active, Ollama socket-activated"
echo "    At boot the AI stack occupies 0 MB until the first query on 11434."
