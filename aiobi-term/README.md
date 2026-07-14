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

## Files

| File               | Purpose                                                  |
|--------------------|----------------------------------------------------------|
| `aiobi-term`       | Python 3 CLI (installed at `/usr/local/bin/aiobi-term`)  |
| `aiobi-term.sh`    | Shell integration (installed at `/etc/profile.d/`)       |

The install is performed by `scripts/17-install-aiobi-term.sh` in the
parent repository.

## Usage

```bash
# Conversational answer (qwen2.5:1.5b)
aiobi-term "What is systemd, in one sentence?"

# Shell-command suggestion (qwen2.5-coder:0.5b)
aiobi-term --cmd "list all listening TCP ports"

# Interactive chat REPL
aiobi-term --chat

# Ctrl-X Ctrl-A on a natural-language input line
# → prints a shell-command suggestion below the prompt
```

## Model choice

| Alias      | Ollama tag             | Size    | Role                            |
|------------|------------------------|---------|---------------------------------|
| chat model | `qwen2.5:1.5b`         | ~1.0 GB | Conversational answers          |
| code model | `qwen2.5-coder:0.5b`   | ~0.4 GB | Shell command generation        |

Both models are pulled once at first boot by
`aiobi-ollama-firstpull.service` (registered by `15-install-ollama.sh`)
and unloaded from memory after five minutes of idleness via
`OLLAMA_KEEP_ALIVE`.
