#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 17 — Terminal AI assistant (aiobi-term)
# ----------------------------------------------------------------------------
# Purpose : install the aiobi-term command-line assistant and its shell
#           readline integration.
#
# Source layout
#   The source lives at aiobi-term/ in the parent repository, edited
#   as first-class files rather than embedded in a heredoc:
#     aiobi-term/aiobi-term         Python 3 CLI entry point (stdlib only)
#     aiobi-term/aiobi-term.sh      shell integration (readline bindings)
#     aiobi-term/aiobi_term/        Python package — knowledge base,
#                                   i18n, rules, engine (stdlib only)
#     aiobi-term/README.md          usage + design contract
#
# Install targets
#   /usr/local/bin/aiobi-term            CLI entry (executable, 0755)
#   /etc/profile.d/aiobi-term.sh         shell integration (readline)
#   /usr/local/lib/aiobi-term/aiobi_term/   Python package (knowledge base)
#
# The package installs to a self-contained path (not to
# /usr/local/lib/pythonX.Y/dist-packages/) so it is independent of the
# system Python's minor version — the CLI adds /usr/local/lib/aiobi-term
# to sys.path at startup.
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
SRC_PKG="$HERE/aiobi-term/aiobi_term"
LIB_DIR=/usr/local/lib/aiobi-term

# ----- 1) Sanity check the source files are present -------------------------
[ -f "$SRC_CLI" ]           || { echo "ERROR: $SRC_CLI missing"; exit 2; }
[ -f "$SRC_SH" ]            || { echo "ERROR: $SRC_SH missing";  exit 2; }
[ -d "$SRC_PKG" ]           || { echo "ERROR: $SRC_PKG package missing"; exit 2; }
[ -d "$SRC_PKG/knowledge" ] || { echo "ERROR: $SRC_PKG/knowledge missing"; exit 2; }

# ----- 2) Install the Python CLI entry point --------------------------------
install -m 0755 "$SRC_CLI" /usr/local/bin/aiobi-term
echo "  installed /usr/local/bin/aiobi-term"

# ----- 3) Install the shell integration -------------------------------------
install -m 0644 "$SRC_SH" /etc/profile.d/aiobi-term.sh
echo "  installed /etc/profile.d/aiobi-term.sh"

# ----- 4) Install the aiobi_term Python package -----------------------------
# Self-contained under /usr/local/lib/aiobi-term/ so it does not depend on
# the system Python's minor version. Any __pycache__ from the source tree
# is stripped so the installed copy starts clean.
install -d -m 0755 "$LIB_DIR"
rm -rf "$LIB_DIR/aiobi_term"
cp -r "$SRC_PKG" "$LIB_DIR/aiobi_term"
find "$LIB_DIR/aiobi_term" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find "$LIB_DIR/aiobi_term" -type d -exec chmod 0755 {} +
find "$LIB_DIR/aiobi_term" -type f -exec chmod 0644 {} +
echo "  installed $LIB_DIR/aiobi_term ($(find "$LIB_DIR/aiobi_term" -name '*.py' | wc -l) Python files)"

# ----- 5) Byte-compile everything for cold-start speed ---------------------
python3 -c "import py_compile; py_compile.compile('/usr/local/bin/aiobi-term', doraise=True)" \
    2>/dev/null || echo "  (CLI byte-compile skipped)"
python3 -m compileall -q "$LIB_DIR/aiobi_term" 2>/dev/null || echo "  (package byte-compile skipped)"

# ----- 6) Verification ------------------------------------------------------
echo
echo "== Verification =="
if head -1 /usr/local/bin/aiobi-term | grep -q python3; then
    echo "  ✓ /usr/local/bin/aiobi-term shebang points at python3"
fi
[ -f /etc/profile.d/aiobi-term.sh ] && echo "  ✓ /etc/profile.d/aiobi-term.sh present"
[ -d "$LIB_DIR/aiobi_term/knowledge/rules" ] && echo "  ✓ $LIB_DIR/aiobi_term/knowledge/rules/ present"

# Knowledge base sanity check — import must succeed from an isolated
# interpreter (matches how the CLI will bootstrap it).
if python3 -c "
import sys
sys.path.insert(0, '$LIB_DIR')
from aiobi_term.knowledge import lookup
from aiobi_term.knowledge.loader import get_all_rules
print(f'  ✓ knowledge base imports; {len(get_all_rules())} rules registered')
" 2>&1; then
    :
else
    echo "  ✗ knowledge base import failed — check $LIB_DIR/aiobi_term/ layout"
fi

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
echo "                      aiobi-term --explain \"netstat -tuln\""
echo "                      Ctrl-X Ctrl-A on a natural-language line"
echo "                      Ctrl-X Ctrl-H after a failed command"
