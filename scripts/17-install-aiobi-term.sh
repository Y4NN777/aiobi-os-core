#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 17 — Terminal AI assistant (aiobi-term)
# ----------------------------------------------------------------------------
# Purpose : install the aiobi-term command-line assistant and its shell
#           readline integration.
#
# Source layout
#   The source lives at aiobi-term/ in the parent repository, edited
#   as a first-class file rather than embedded in a heredoc:
#     aiobi-term/aiobi-term      Python 3 CLI, stdlib only (no pip)
#     aiobi-term/aiobi-term.sh   shell integration (Ctrl-X Ctrl-A binding)
#     aiobi-term/README.md       usage + design contract
#
# Install targets
#   /usr/local/bin/aiobi-term       (executable, 0755)
#   /etc/profile.d/aiobi-term.sh    (loaded for every interactive login)
#
# Contract inherited from aiobi-term/README.md :
#   - loopback-only (127.0.0.1:11434)
#   - stdlib-only Python
#   - human confirmation for every shell command (never auto-executed)
#
# Idempotent: overwrites destination files on every run.
#
# Ordering: run after 15-install-ollama.sh so the Ollama daemon endpoint
# is available for a smoke test at the end.
# ============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi — 17-install-aiobi-term.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC_CLI="$HERE/aiobi-term/aiobi-term"
SRC_SH="$HERE/aiobi-term/aiobi-term.sh"

# ----- 1) Sanity check the source files are present -------------------------
[ -f "$SRC_CLI" ] || { echo "ERROR: $SRC_CLI missing"; exit 2; }
[ -f "$SRC_SH" ]  || { echo "ERROR: $SRC_SH missing";  exit 2; }

# ----- 2) Install the Python CLI --------------------------------------------
install -m 0755 "$SRC_CLI" /usr/local/bin/aiobi-term
echo "  installed /usr/local/bin/aiobi-term"

# ----- 3) Install the shell integration -------------------------------------
install -m 0644 "$SRC_SH" /etc/profile.d/aiobi-term.sh
echo "  installed /etc/profile.d/aiobi-term.sh"

# ----- 4) Byte-compile so first launch is not slow --------------------------
python3 -c "import py_compile; py_compile.compile('/usr/local/bin/aiobi-term', doraise=True)" \
    2>/dev/null || echo "  (byte-compile skipped)"

# ----- 5) Verification ------------------------------------------------------
echo
echo "== Verification =="
if head -1 /usr/local/bin/aiobi-term | grep -q python3; then
    echo "  ✓ /usr/local/bin/aiobi-term shebang points at python3"
fi
[ -f /etc/profile.d/aiobi-term.sh ] && echo "  ✓ /etc/profile.d/aiobi-term.sh present"

# Optional smoke test: if the Ollama daemon is reachable, do a trivial call.
if curl -sf --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo "  smoke test: querying local daemon..."
    /usr/local/bin/aiobi-term --cmd "print hello" 2>/dev/null | head -3 \
        || echo "  (smoke test skipped — models may not be pulled yet)"
else
    echo "  smoke test skipped (Ollama daemon not reachable)"
fi

echo "==> 17 done — aiobi-term installed"
echo "    Try after login:  aiobi-term \"what is systemd?\""
echo "                      aiobi-term --cmd \"list listening ports\""
echo "                      Ctrl-X Ctrl-A on a natural-language line"
