# Existing-diagram update specifications

Textual change specs for the seven pre-existing `design/*.png` diagrams,
cross-checked against the real repository at
`/home/ogu/Projects/AïobiOS-Guidance/aiobi-os-core/` (scripts/, aiobi-term/,
aiobi-update/). Every claim below is anchored to a source file; where the
audit's original wording could not be confirmed against code, it is marked
**to verify** rather than restated as fact.

---

## 1. `aiobi_component.png` — verdict: REPLACE

Superseded in full by **Figure 4.6 — AI-Layer Overview** (`01-ai-layer-overview.md`).
No incremental edit is proposed; the stale "Edge AI" box (`ollama`,
`pythonMiddleware: BashOrchestrator`, `anythingLLM`) is retired.

## 2. `secure_boot_seq.png` — verdict: KEEP AS-IS

No AI-composition-phase change touches the boot chain. One item flagged by
the original audit remains open and is restated here as **to verify**: the
diagram's step 6 (`enableFirewall()` / UFW) was not independently
re-confirmed against a `ufw`-configuring script in `scripts/` — only the
AI-specific `20-ai-firewall.sh` (iptables OUTPUT REJECT on port 11434) was
found. If a UFW-provisioning script exists elsewhere in the repository, this
diagram should be re-checked against it; otherwise the label may need
correcting to name the actual mechanism.

## 3. `security_layer.png` — verdict: UPDATE

Add a third component, verified against `scripts/20-ai-firewall.sh`:

```
iptables/ip6tables — AI-Egress-Filter
  OUTPUT chain, IPv4 (rules.v4) and IPv6 (rules.v6):
    ACCEPT tcp dpt:11434 -> 127.0.0.0/8   (IPv4) / ::1/128 (IPv6)
    REJECT tcp dpt:11434 -> * (icmp-port-unreachable / icmp6-port-unreachable)
  Installed persistently via iptables-persistent / netfilter-persistent.
  Scope label: zero-data-leak (defense-in-depth alongside loopback bind).
```

This is additive next to the existing `luks: DiskEncryption` and
`ufw: NetworkFirewall` components — no restructuring needed. See also
**Figure 4.12 — Zero-Data-Leak Defense-in-Depth** for the fuller layered
argument this single component feeds into.

## 4. `ai_usecase.png` — verdict: UPDATE

Add two elements, verified against `aiobi-term/aiobi-term` (`do_explain`,
`is_destructive`, `DESTRUCTIVE_PATTERNS`):

- **`«include»` ellipse: "Explain failed command (two-layer)"** — feeds into
  the existing "Serve inference API" node only on a knowledge-base miss;
  the knowledge-base hit path (Figure 4.10) never reaches the LLM at all
  and should be drawn as a short-circuit, not a sub-step of inference.
- **`«extend»` ellipse: "Destructive-pattern guardrail"** — extends the
  "Translate NL to shell command" use case; fires only on `--cmd` output,
  independent of the model call itself (it is a client-side regex check
  over ten patterns: `rm -rf`, `dd of=/dev/`, `mkfs.*`, `fdisk`, world-write
  `chmod`, recursive system-path `chown`, `/etc/` truncation redirects,
  power-state commands, fork bombs, `curl|sh` piping).

## 5. `ai_deployment.png` — verdict: UPDATE

Three corrections, all verified against source:

1. **Binary name**: the shipped CLI is `aiobi-term`
   (`scripts/17-install-aiobi-term.sh` installs to `/usr/local/bin/aiobi-term`),
   not `aiobi-ai`.
2. **Model store**: two models are actually pre-pulled by
   `scripts/15-install-ollama.sh`, not a single unified one and not the
   originally-diagrammed pair:
   - `qwen2.5:1.5b` (~986 MB) — serves **both** `aiobi-term` modes (chat
     and cmd), replacing the rejected `qwen2.5-coder:0.5b` split.
   - `qwen3-vl:2b-instruct-q8_0` (~2.6 GB) — serves **AnythingLLM Desktop**
     only, for multimodal chat.
   The diagram's original single "coder" model box is stale; the
   replacement is not "one unified model" across the whole AI layer but
   "one model per consumer, sharing one daemon."
3. **Enforcement node**: add the `iptables`/`ip6tables` egress filter as a
   modelled component acting on `ollama.service`, not a sticky-note claim
   (see item 3 above and Figure 4.12).

Also add the proxy indirection (`ollama-proxy.socket/.service` in front of
`ollama.service`) — see item 6, shared with the model-lifecycle diagram.

## 6. `ai_model_lifecycle.png` — verdict: UPDATE (superseded by a dedicated diagram)

Fully replaced by **`ollama-daemon-state.puml`** (Figure 4.8), which models
the verified two-hop chain from `scripts/19-tune-ram.sh`:

```
ollama-proxy.socket   ListenStream=127.0.0.1:11434 (public, socket-activated)
  -> ollama-proxy.service   ExecStartPre curl-polls 127.0.0.1:11435/api/tags
                            (bounded 30 x 1s retries), then
                            ExecStart=systemd-socket-proxyd --exit-idle-time=300
                            127.0.0.1:11435
  -> ollama.service          OLLAMA_HOST=127.0.0.1:11435, OLLAMA_KEEP_ALIVE=5m,
                            StopWhenUnneeded=yes, autostart symlink removed
```

The prior single-tier `Unloaded -> Loading -> Loaded -> Inferring` shape
collapsed this proxy indirection; it is now explicit, matching the code
exactly (`Requires=ollama.service`/`After=` in the proxy unit, the
`ExecStartPre` race-avoidance guard, and `StopWhenUnneeded=yes` in the
`ollama.service` drop-in).

## 7. `ai_sequence.png` — verdict: UPDATE + ADD COMPANION

Two actions:

1. **In-place fix** (small diff): rename `aiobi-ai` to `aiobi-term` and
   correct the backend model reference to `qwen2.5:1.5b` (the diagram's
   `qwen2.5-coder:0.5b` backend is the rejected, non-shipped model —
   verified: `aiobi-term/aiobi-term` line `MODEL = "qwen2.5:1.5b"`).
2. **New companion sequence diagrams** (not folded into this one, per the
   original audit's scope call): the `--cmd` round trip is now fully
   modelled in `aiobi-term-cmd-sequence.puml` (Figure 4.11) with the
   destructive-pattern guardrail and daemon-unreachable branch drawn
   explicitly; the `--explain` two-layer flow is its own diagram
   (`aiobi-term-explain-sequence.puml`, Figure 4.10).
