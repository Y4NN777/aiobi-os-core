# aiobi-term

The Aïobi OS terminal AI assistant. A Python 3 command-line wrapper around
the locally-bound Ollama daemon (`127.0.0.1:11434`) that lets any shell
user translate natural language into shell commands or hold a short
conversation with a local language model.

## Design

- **Loopback only.** Every request goes to `127.0.0.1:11434`; no other
  host is ever contacted. Aligned with the Aïobi zero-data-leak posture.
- **stdlib only.** No `pip install` required; the tool uses only
  `urllib`, `argparse`, `json`, and `re` from the Python standard
  library.
- **Human confirmation for every command.** `aiobi-term --cmd` prints
  the suggestion; the user decides whether to run it. `aiobi-term`
  itself never executes shell commands.
- **Software-intelligence recovery loop.** `--explain` closes the
  feedback loop when a command fails: `aiobi-term --explain "<cmd>"`
  (or `Ctrl-X Ctrl-H` on the last history entry) explains the likely
  cause on Aïobi OS and proposes a corrected alternative. Two-layer
  architecture:
    1. **Deterministic knowledge base** (see `aiobi_term/knowledge/`) —
       ~50 curated rules pattern-match the command shape and/or the
       shell error text (passed via `--error`). When a rule hits, the
       localized cause + corrective one-liner is printed instantly, with
       no LLM call. Zero latency, zero hallucination, deterministic
       across identical inputs. Categories: deprecated tools (netstat,
       ifconfig, nslookup, telnet…), Aïobi-purged apps (snap,
       libreoffice, rhythmbox…), systemd/filesystem/network/
       package-manager/python/git/ssh/docker/display errors.
    2. **LLM fallback** — only invoked when the knowledge base misses.
       Strict two-line format (`cause` + `Try: <cmd>`), deterministic
       decoding, no re-execution of the failing command.
- **Destructive-pattern guardrail.** The CODE_SYSTEM prompt asks the
  model to emit destructive suggestions as *two lines* — a `# ` warning
  first, then the actual command — so the user sees both the risk and
  the command ready to review. When the model omits the warning and
  the output matches a known dangerous pattern (`rm -rf`, `dd of=/dev/`,
  `mkfs`, `chmod 777 /`, recursive `chown` on system paths, `shutdown`,
  fork bomb, `curl … | sh`, etc.), `do_command` **prepends** a
  `# WARNING` line above the raw command so the risk is always visible.

## Files

| File / directory    | Purpose                                                                                       |
|---------------------|-----------------------------------------------------------------------------------------------|
| `aiobi-term`        | Python 3 CLI entry point — installed at `/usr/local/bin/aiobi-term`                           |
| `aiobi-term.sh`     | Shell integration (readline bindings) — installed at `/etc/profile.d/aiobi-term.sh`           |
| `aiobi_term/`       | Python package (knowledge base + engine + i18n + rules) — installed at `/usr/local/lib/aiobi-term/aiobi_term/` |

The install is performed by `scripts/17-install-aiobi-term.sh` in the
parent repository. The package lives under `/usr/local/lib/aiobi-term/`
(not under `/usr/local/lib/pythonX.Y/dist-packages/`) so it is
independent of the system Python's minor version; the CLI adds the
directory to `sys.path` at startup.

### Knowledge base layout

Everything below `aiobi_term/knowledge/`:

| Module          | Role                                                              |
|-----------------|-------------------------------------------------------------------|
| `rule.py`       | Typed dataclasses: `Rule`, `Match`, `Category`, `LookupResult`    |
| `engine.py`     | `lookup(command, error, lang) → LookupResult \| None` — matcher, priority resolver, template renderer for `{cmd}`, `{cmd_bin}`, `{arg1}`, `{arg2}`, `{argN}` |
| `i18n.py`       | `Translator` — reads `$AIOBI_TERM_LANG` (override) then `$LANG`; falls back to English if a key is missing in the requested language |
| `loader.py`     | Aggregates `RULES` from every module in `rules/` — explicit imports, no runtime magic |
| `rules/*.py`    | 11 rule modules, one per category (~5-15 rules each, ~50 total)   |

### Adding a rule (V1.1+)

1. Add a `Rule(...)` entry to the relevant `rules/<category>.py`.
2. Add its `cause_key` string to both `messages/en` (`i18n.MESSAGES_EN`)
   and `messages/fr` (`i18n.MESSAGES_FR`) in `i18n.py`.
3. Confirm the rule fires on realistic inputs — run the module
   directly against the smoke-test harness in `test_all.sh`
   (V1.1 candidate).

## Usage

```bash
# Conversational answer
aiobi-term "What is systemd, in one sentence?"

# Shell-command suggestion (deterministic decoding + few-shot prompt)
aiobi-term --cmd "list all listening TCP ports"

# Explain why a shell command failed and propose an alternative
aiobi-term --explain "netstat -tuln"

# Same, with the actual shell error output for a tighter diagnosis
aiobi-term --explain "systemctl start foo" --error "Failed to start foo.service: Unit foo.service not found."

# Interactive chat REPL
aiobi-term --chat

# Ctrl-X Ctrl-A on a natural-language input line
# → prints a shell-command suggestion below the prompt
# Ctrl-X Ctrl-H after a failed command
# → prints a one-sentence explanation + a corrected alternative
```

## Model choice

`aiobi-term` uses a single small language model for both modes; the two
modes differ only in system prompt and sampling.

| Ollama tag       | Size    | Role in aiobi-term                                    |
|------------------|---------|-------------------------------------------------------|
| `qwen2.5:1.5b`   | ~1.0 GB | Chat mode (default sampling) + `--cmd` mode (T=0, few-shot) |

Consolidating on one model saves ~400 MB of RAM footprint compared with
running a separate coder variant. The `--cmd` mode compensates for the
absence of a code-tuned model with:

- **Deterministic decoding** — `temperature=0`, `top_k=1`, `top_p=0.1`,
  so the same request produces the same command.
- **Few-shot prompt** — the `CODE_SYSTEM` prompt embeds six
  request-to-command examples (list services, disk free, top by memory,
  list listening TCP ports via `ss`, delete-log destructive warning,
  format-disk destructive warning, wipe-disk destructive warning) plus
  an explicit clause that steers toward modern Ubuntu 24.04 tools
  (`ss` over `netstat`, `ip` over `ifconfig`, `dig` over `nslookup`,
  `journalctl` over `/var/log` tailing).
- **Post-processing** — `strip_fences()` removes markdown fences,
  wrapping backticks, leading `$`, and trailing prose, then collapses
  the response to its first non-empty line.
- **Destructive-pattern guardrail** — `is_destructive()` runs a regex
  safety net (see the Design section above) that replaces the model's
  output with a warning comment whenever a known dangerous pattern
  (`rm -rf`, `dd of=/dev/`, `mkfs`, `chmod 777 /`, `chown -R … /etc`,
  `shutdown`, fork bomb, `curl … | sh`) slips through the prompt.

The model is pulled once at first boot by `aiobi-ollama-firstpull.service`
(registered by `15-install-ollama.sh`) alongside
`qwen3-vl:2b-instruct-q8_0` (the multimodal chat model consumed by the
AnythingLLM desktop app). Both models are unloaded from memory after
five minutes of idleness via `OLLAMA_KEEP_ALIVE`.
