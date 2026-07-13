#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 17 — Terminal AI assistant (Python middleware)
# ----------------------------------------------------------------------------
# Purpose : install the `aiobi-ai` command-line assistant and its Bash / Zsh
#           integration. The command lets the user express a request in
#           natural language and receive either a shell command suggestion
#           (via qwen2.5-coder:0.5b) or a conversational answer (via
#           qwen2.5:1.5b), talking to the locally-bound Ollama daemon on
#           127.0.0.1:11434.
#
# Delivers
#   - /usr/local/bin/aiobi-ai         Python 3 CLI (stdlib only, no pip)
#   - /etc/profile.d/aiobi-ai.sh      shell functions (`ai`, `cmd`) + Ctrl-X Ctrl-A binding
#
# Shell integration
#   - `ai "<question>"`  --- conversational answer (qwen2.5:1.5b)
#   - `cmd "<request>"`  --- shell-command suggestion (qwen2.5-coder:0.5b)
#   - Ctrl-X Ctrl-A      --- readline binding: sends the current input line
#                            through `aiobi-ai --cmd` and prints the
#                            suggestion. Press Enter to run, edit, or Ctrl-C.
#
# Zero-data-leak: every request goes to http://127.0.0.1:11434 — the
# loopback endpoint bound by 15-install-ollama.sh. No network egress.
#
# Idempotent: the CLI and shell hook are rewritten on every run.
#
# Ordering: run after 15-install-ollama.sh. Works even if the daemon is
# not currently active (the CLI prints a friendly error on connection
# refused).
# ============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi — 17-install-ai-cli.sh"

# ----- 1) Install /usr/local/bin/aiobi-ai -----------------------------------
tee /usr/local/bin/aiobi-ai > /dev/null << 'PYEOF'
#!/usr/bin/env python3
# aiobi-ai --- terminal AI assistant for Aïobi OS
#
# Talks to a locally-bound Ollama daemon on http://127.0.0.1:11434.
# Two modes:
#   aiobi-ai "<question>"            conversational (qwen2.5:1.5b)
#   aiobi-ai --cmd "<request>"       shell command generation (qwen2.5-coder:0.5b)
#   aiobi-ai --chat                  interactive REPL
#
# stdlib only --- no pip install required.

import argparse
import json
import re
import sys
import urllib.request
import urllib.error


OLLAMA_ENDPOINT = "http://127.0.0.1:11434/api/generate"

CHAT_MODEL = "qwen2.5:1.5b"
CODE_MODEL = "qwen2.5-coder:0.5b"

CHAT_SYSTEM = (
    "You are Aïobi Assistant, the built-in AI of Aïobi OS. Answer the "
    "user's question concisely and in the language they used. If they "
    "ask about system administration, prefer Ubuntu 24.04 conventions."
)

CODE_SYSTEM = (
    "You translate the user's natural-language request into a single "
    "safe shell command for Ubuntu 24.04. Return ONLY the command, on "
    "one line, with no explanation, no code fence, no leading '$' and "
    "no trailing punctuation. If the request is destructive or ambiguous, "
    "prefix the command with a single '# ' and a one-sentence warning."
)


def call_ollama(model: str, system: str, prompt: str, timeout: float = 60.0) -> str:
    body = json.dumps({
        "model": model,
        "system": system,
        "prompt": prompt,
        "stream": False,
    }).encode("utf-8")

    req = urllib.request.Request(
        OLLAMA_ENDPOINT,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.load(resp)
            return (data.get("response") or "").strip()
    except urllib.error.URLError as exc:
        sys.stderr.write(
            "aiobi-ai: cannot reach the local Ollama daemon on 127.0.0.1:11434\n"
            f"         reason: {exc.reason}\n"
            "         hint  : run `systemctl start ollama` and retry\n"
        )
        sys.exit(2)
    except Exception as exc:
        sys.stderr.write(f"aiobi-ai: unexpected error: {exc}\n")
        sys.exit(3)


def strip_fences(text: str) -> str:
    """Strip markdown code fences and leading '$ ' from a coder response."""
    text = text.strip()
    text = re.sub(r"^```[a-zA-Z0-9]*\n", "", text)
    text = re.sub(r"\n```\s*$", "", text)
    text = text.strip()
    # Drop a single leading '$ ' or '$' the model may add anyway.
    if text.startswith("$ "):
        text = text[2:]
    elif text.startswith("$"):
        text = text[1:].lstrip()
    return text


def do_command(request: str) -> None:
    response = call_ollama(CODE_MODEL, CODE_SYSTEM, request)
    print(strip_fences(response))


def do_chat(question: str) -> None:
    response = call_ollama(CHAT_MODEL, CHAT_SYSTEM, question)
    print(response)


def do_repl() -> None:
    print("aiobi-ai --- interactive chat. Type 'exit' to quit.")
    print("            (uses qwen2.5:1.5b on 127.0.0.1:11434)")
    while True:
        try:
            line = input("you> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if not line:
            continue
        if line.lower() in {"exit", "quit", "bye"}:
            return
        print("ai>  " + call_ollama(CHAT_MODEL, CHAT_SYSTEM, line))


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="aiobi-ai",
        description="Aïobi OS terminal AI assistant "
                    "(talks to local Ollama on 127.0.0.1:11434).",
    )
    parser.add_argument("--cmd", action="store_true",
                        help="Return a shell command instead of a chat answer.")
    parser.add_argument("--chat", action="store_true",
                        help="Start an interactive chat REPL.")
    parser.add_argument("prompt", nargs="*",
                        help="The question or request. Read from stdin if empty.")
    args = parser.parse_args()

    if args.chat:
        do_repl()
        return 0

    if args.prompt:
        request = " ".join(args.prompt)
    elif not sys.stdin.isatty():
        request = sys.stdin.read().strip()
    else:
        parser.print_help(sys.stderr)
        return 1

    if args.cmd:
        do_command(request)
    else:
        do_chat(request)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF
chmod 755 /usr/local/bin/aiobi-ai
echo "  installed /usr/local/bin/aiobi-ai"

# ----- 2) Install /etc/profile.d/aiobi-ai.sh --------------------------------
tee /etc/profile.d/aiobi-ai.sh > /dev/null << 'SHEOF'
# Aïobi OS --- terminal AI assistant integration.
# Loaded by /etc/profile for every interactive login shell.

# `ai "..."` --- conversational answer via qwen2.5:1.5b
ai() {
    if [ "$#" -eq 0 ]; then
        aiobi-ai --chat
    else
        aiobi-ai "$@"
    fi
}

# `cmd "..."` --- shell-command generation via qwen2.5-coder:0.5b
cmd() {
    if [ "$#" -eq 0 ]; then
        printf 'usage: cmd "<what you want the shell to do>"\n' >&2
        return 2
    fi
    aiobi-ai --cmd "$@"
}

# Bash readline: Ctrl-X Ctrl-A --- send the current line through `cmd` and
# display the suggested shell command below the prompt. The user then
# presses Enter to run it, edits it, or hits Ctrl-C.
if [ -n "${BASH_VERSION:-}" ]; then
    bind -x '"\C-x\C-a": aiobi-ai --cmd "$READLINE_LINE"' 2>/dev/null || true
fi

# Zsh: bind the same shortcut using ZLE.
if [ -n "${ZSH_VERSION:-}" ]; then
    _aiobi_ai_cmd() {
        aiobi-ai --cmd "$BUFFER"
        zle reset-prompt
    }
    zle -N _aiobi_ai_cmd
    bindkey '^X^A' _aiobi_ai_cmd 2>/dev/null || true
fi
SHEOF
chmod 644 /etc/profile.d/aiobi-ai.sh
echo "  installed /etc/profile.d/aiobi-ai.sh"

# ----- 3) Byte-compile the Python CLI so first launch is not slow -----------
python3 -c "import py_compile; py_compile.compile('/usr/local/bin/aiobi-ai', doraise=True)" \
    2>/dev/null || echo "  (byte-compile skipped)"

# ----- 4) Verification --------------------------------------------------------
echo
echo "== Verification =="
if command -v python3 >/dev/null 2>&1; then
    if head -1 /usr/local/bin/aiobi-ai | grep -q python3; then
        echo "  ✓ /usr/local/bin/aiobi-ai present"
    fi
fi
[ -f /etc/profile.d/aiobi-ai.sh ] && echo "  ✓ /etc/profile.d/aiobi-ai.sh present"

echo "==> 17 done — aiobi-ai CLI + shell integration installed"
echo "    Try after login:  ai \"what is systemd?\""
echo "                      cmd \"list all listening ports\""
echo "                      Ctrl-X Ctrl-A on a natural-language line"
