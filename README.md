# aiobi-os-core

Reproducible customization pipeline for **Aïobi OS**, a customized Linux
distribution derived from Ubuntu 24.04 LTS (Noble) with GNOME 46. This
repository contains the scripts, configuration files, and asset stubs
that transform a stock Ubuntu ISO into an Aïobi OS ISO.

Companion artefact to the Bachelor's thesis *Design and Deployment of a
Customized Linux Operating System with Native AI Integration: Case of
Aïobi OS* (RN Yanis Axel DABO, Burkina Institute of Technology).

## What this repository is

- **21 idempotent shell scripts** that apply the six customization
  layers (system identity, visual identity, shell composition,
  application inventory, on-device AI, persistence & lockdown) plus a
  validation script and an all-in-one orchestrator (`run-all.sh`).
- **`aiobi-term/`** — the on-device terminal AI assistant: a stdlib-only
  Python CLI, a Python package with a deterministic knowledge base
  (~50 curated rules across deprecated tools, Aïobi-purged apps,
  systemd/filesystem/network/package-mgr/python/git/ssh/docker/display
  errors, EN + FR i18n), and a Bash/Zsh readline integration
  (`Ctrl-X Ctrl-A` for `--cmd`, `Ctrl-X Ctrl-H` for `--explain`).
- **`design/`** — the architecture diagrams (UMLs) that back the thesis
  chapters: component view, secure-boot sequence, security layer,
  AI use-case / deployment / lifecycle / sequence.
- **`dconf` keyfiles and profile** that enforce brand defaults at the
  system level (panel layout, wallpaper, terminal palette, GTK theme)
  while preserving user freedom on non-negotiable keys (colour scheme,
  wallpaper choice, accent).
- **SVG icon placeholders** for the AI-native surface (chat, terminal,
  status indicators) awaiting their production art pass.
- **Zero-data-leak posture, enforced at the kernel level.** The Ollama
  daemon binds `127.0.0.1` only; an `iptables` + `ip6tables` OUTPUT
  rule rejects any TCP :11434 traffic to non-loopback destinations
  regardless of application configuration.

The scripts are intended to be run **inside a Cubic chroot** during ISO
build, and are also safe to run on an installed VM for post-install
polish.

## Repository layout

```
aiobi-os-core/
├── README.md
├── LICENSE
├── SECURITY.md
├── .gitignore
├── scripts/
│   ├── 01-install-extensions.sh    # dash-to-panel + user-theme
│   ├── 02-configure-panel.sh       # dconf keyfile — panel layout
│   ├── 03-inject-theme.sh          # GTK 3+4 theme (Yaru clone + sed + gresource)
│   ├── 04-install-icons.sh         # Papirus recolour + Aïobi placeholders
│   ├── 04b-override-icons.sh       # icon swap for the AI-native surface
│   ├── 05-rebrand-os.sh            # OS identity + GRUB + MOTD + first-boot service
│   ├── 06-apply-persistence.sh     # dconf profile + locks + skel + fonts
│   ├── 07-validate.sh              # PASS/FAIL check against milestone criteria
│   ├── 08-inject-shell-theme.sh    # GNOME Shell theme (Yaru clone + sed)
│   ├── 09-terminal-profile.sh      # GNOME Terminal palette
│   ├── 10-snap-final-purge.sh      # snap removal + APT pin
│   ├── 11-apt-brand-alias.sh       # /etc/hosts + DEB822 mirror alias
│   ├── 12-wine-proton-install.sh   # Wine 9.0 + GE-Proton + MIME handlers
│   ├── 13-productivity-stack.sh    # OnlyOffice + Brave + VLC + Flameshot + Flatpaks
│   ├── 15-install-ollama.sh        # Ollama daemon + first-boot model pull (loopback)
│   ├── 17-install-aiobi-term.sh    # aiobi-term CLI + knowledge package + shell integration
│   ├── 18-install-anythingllm.sh   # AnythingLLM Desktop AppImage
│   ├── 19-tune-ram.sh              # zRAM (zstd) + Ollama socket activation
│   ├── 20-ai-firewall.sh           # iptables OUTPUT REJECT :11434 non-loopback
│   ├── 21-configure-bash-completion.sh  # TAB menu-complete + argcomplete + skel setup
│   └── run-all.sh                  # orchestrator (no number — entry point, not a step)
├── aiobi-term/
│   ├── aiobi-term                  # Python 3 CLI entry point (stdlib only)
│   ├── aiobi-term.sh               # Bash/Zsh readline bindings
│   │                               # (Ctrl-X Ctrl-A = --cmd, Ctrl-X Ctrl-H = --explain)
│   ├── aiobi_term/                 # Python package (installed to /usr/local/lib/aiobi-term/)
│   │   ├── __init__.py
│   │   └── knowledge/
│   │       ├── __init__.py         # public API: lookup, LookupResult, Rule, Match, Category
│   │       ├── rule.py             # typed dataclasses (Rule, Match, Category, LookupResult)
│   │       ├── engine.py           # matcher + priority resolver + template renderer
│   │       ├── i18n.py             # Translator (LANG detection) + EN + FR message tables
│   │       ├── loader.py           # rule aggregator (explicit imports, no runtime magic)
│   │       └── rules/              # 11 rule modules, ~50 curated rules total
│   │           ├── deprecated_tools.py
│   │           ├── aiobi_purged.py
│   │           ├── systemd_errors.py
│   │           ├── filesystem_errors.py
│   │           ├── network_errors.py
│   │           ├── package_mgr.py
│   │           ├── python_errors.py
│   │           ├── git_errors.py
│   │           ├── ssh_errors.py
│   │           ├── docker_errors.py
│   │           └── xorg_wayland.py
│   └── README.md                   # design + usage
├── design/
│   ├── aiobi_component.png         # core-OS component view
│   ├── secure_boot_seq.png         # secure-boot sequence
│   ├── security_layer.png          # zero-data-leak security layer
│   ├── ai_usecase.png              # AI layer — use cases
│   ├── ai_deployment.png           # AI layer — deployment (loopback bind)
│   ├── ai_model_lifecycle.png      # AI layer — model lifecycle (pull → serve → unload)
│   ├── ai_sequence.png             # AI layer — request sequence (aiobi-term ↔ Ollama)
│   └── README.md                   # index + regeneration notes
├── config/
│   ├── dconf-profile               # /etc/dconf/profile/user
│   ├── aiobi-panel.dconf           # panel layout + colours
│   ├── aiobi-wallpaper.dconf       # default wallpaper (unlocked)
│   ├── aiobi-terminal.dconf        # GNOME Terminal 16-colour palette
│   └── local.d/
│       └── 00-aiobi-branding       # gtk/icon/font/color-scheme defaults
├── aiobi-theme/                    # legacy overlay stylesheets (superseded by script 03)
└── icons/                          # AI-native SVG placeholders
```

Note: `16-` is deliberately skipped; PWA-wrapper work has been descoped
for the current milestone.

## Usage

### Inside a Cubic chroot (ISO build)

```bash
# 1. Copy the repository into the chroot (any writable path).
scp -r aiobi-os-core/ <chroot-host>:/tmp/

# 2. Open the Cubic terminal (root inside the chroot).
cd /tmp/aiobi-os-core

# 3. Recommended --- one-shot orchestrator (runs all layers + validation):
bash scripts/run-all.sh

# Or run individually, in the orchestrator's order:
bash scripts/01-install-extensions.sh
bash scripts/02-configure-panel.sh
bash scripts/03-inject-theme.sh
bash scripts/04-install-icons.sh
bash scripts/05-rebrand-os.sh
bash scripts/08-inject-shell-theme.sh
bash scripts/10-snap-final-purge.sh
bash scripts/11-apt-brand-alias.sh
bash scripts/12-wine-proton-install.sh
bash scripts/13-productivity-stack.sh
bash scripts/15-install-ollama.sh
bash scripts/17-install-aiobi-term.sh
bash scripts/18-install-anythingllm.sh
bash scripts/19-tune-ram.sh
bash scripts/20-ai-firewall.sh
bash scripts/21-configure-bash-completion.sh
bash scripts/06-apply-persistence.sh
bash scripts/09-terminal-profile.sh
bash scripts/07-validate.sh
```

### On an installed VM (post-install polish)

Same commands as above; the scripts detect the presence of an active
D-Bus session and adapt (live extension enablement, per-user dconf
writes). Persistence is achieved through system-wide `dconf` keyfiles,
so the effect survives reboots regardless of the environment.

## Idempotency

Every script backs up any file it modifies on first run and restores
from the backup before re-applying its changes on subsequent runs.
Re-running the orchestrator or any individual script is safe. Backups
live at predictable suffixes (`.aiobi.bak`, `.magenta.bak`, etc.)
alongside the modified files.

## AI layer

The AI layer is split across two consumers of a single locally-bound
Ollama daemon.

| Consumer                | Model tag                              | Role                                                    |
|-------------------------|----------------------------------------|---------------------------------------------------------|
| `aiobi-term` (terminal) | `qwen2.5:1.5b`                         | Chat + shell-command extraction (single model, two system prompts, deterministic decoding for `--cmd`) |
| `AnythingLLM` (desktop) | `qwen3-vl:2b-instruct-q8_0`            | Multi-modal chat (text + image), Desktop Assistant popup |

Both models are pulled on the first boot by `aiobi-ollama-firstpull.service`
(registered by `15-install-ollama.sh`), not baked into the ISO.

**Memory posture.** The Ollama daemon is socket-activated and stops
when unneeded: after `OLLAMA_KEEP_ALIVE=5m` of idleness, models are
unloaded and the daemon converges to zero resident memory.
`systemd-socket-proxyd` on `127.0.0.1:11434` forwards to the private
backend on `127.0.0.1:11435`, giving the socket-activation trigger
point.

**Zero-data-leak posture.** The daemon binds `127.0.0.1` only; script
`20-ai-firewall.sh` installs an `iptables` + `ip6tables` OUTPUT rule
that rejects TCP :11434 to any non-loopback destination. Any
misconfigured client (or bundled Ollama from a third-party desktop
app) attempting to reach an external Ollama endpoint fails at the
kernel filter.

**Verified end-to-end.** The `07-validate.sh` acceptance script and
manual measurements confirm loopback binding, kernel-level rejection
counters at zero, and `StopWhenUnneeded` returning the AI subsystem to
its idle memory baseline after each session.

## Design tokens

| Token             | Value       | Role                              |
|-------------------|-------------|-----------------------------------|
| `aio-black`       | `#0F1010`   | Primary background                |
| `aio-white`       | `#F8F8F9`   | Primary foreground                |
| `aio-violet`      | `#7233CD`   | Primary accent                    |
| `aio-violet-700`  | `#5C24A8`   | Press / active                    |
| `aio-violet-300`  | `#B593E4`   | Hover / disabled                  |

## Locked vs unlocked settings

The `06-apply-persistence.sh` script installs `dconf` locks on the
brand-critical keys and deliberately leaves user-freedom keys unlocked.

| Key                                             | Status    | Reason               |
|-------------------------------------------------|-----------|----------------------|
| `gtk-theme` / `icon-theme` / `font-name`        | LOCKED    | brand-critical       |
| `monospace-font-name`                           | LOCKED    | brand-critical       |
| `enabled-extensions` / `disabled-extensions`    | LOCKED    | dock layout integrity|
| `color-scheme` (light / dark)                   | UNLOCKED  | user freedom         |
| `picture-uri` (wallpaper)                       | UNLOCKED  | user freedom         |
| `accent-color`                                  | UNLOCKED  | user freedom         |

## Chroot caveats (handled inside the scripts)

- **No D-Bus / no live shell session.** Live `gnome-extensions enable`
  would fail. Script `01` detects the missing `$DISPLAY` and
  `$WAYLAND_DISPLAY` and silently skips live enablement; the system
  `dconf` overrides (`06`) handle enablement at first user login.
- **No systemd inside chroot.** No `systemctl` calls. `dconf update`
  is a pure file compile and safe.
- **Stale APT index.** `apt-get update` runs at the top of `01` and
  `04`.
- **`add-apt-repository` failures on rebranded chroot.** Handled by
  writing entries under `sources.list.d/` manually where necessary.

## References

- freedesktop.org `os-release` specification.
- Debian `dpkg-divert(1)` man page.
- GNOME administrator guide (dconf profiles, keyfiles, lockdown).
- Ubuntu Yaru community theme.
- Papirus icon theme upstream.
- Cubic --- Custom Ubuntu ISO Creator.

## License

MIT --- see `LICENSE`.
