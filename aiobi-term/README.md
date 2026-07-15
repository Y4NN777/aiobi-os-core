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
- **Destructive-pattern guardrail.** The CODE_SYSTEM prompt asks the
  model to prefix destructive suggestions with `# `. Because a 1.5B
  model does not always comply, `do_command` runs a regex safety net
  after `strip_fences()`: any output matching a known dangerous
  pattern (`rm -rf`, `dd of=/dev/`, `mkfs`, `chmod 777 /`, recursive
  `chown` on system paths, `shutdown`, fork bomb, `curl … | sh`, etc.)
  is *replaced* with a warning comment. Zero accidental execution of
  a paste from `aiobi-term`.

## Files

| File               | Purpose                                                  |
|--------------------|----------------------------------------------------------|
| `aiobi-term`       | Python 3 CLI (installed at `/usr/local/bin/aiobi-term`)  |
| `aiobi-term.sh`    | Shell integration (installed at `/etc/profile.d/`)       |

The install is performed by `scripts/17-install-aiobi-term.sh` in the
parent repository.

## Usage

```bash
# Conversational answer
aiobi-term "What is systemd, in one sentence?"

# Shell-command suggestion (deterministic decoding + few-shot prompt)
aiobi-term --cmd "list all listening TCP ports"

# Interactive chat REPL
aiobi-term --chat

# Ctrl-X Ctrl-A on a natural-language input line
# → prints a shell-command suggestion below the prompt
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
