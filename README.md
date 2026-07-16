# aiobi-os-core

Chroot-time customization pipeline and first-class subsystems for
**Aïobi OS** — a customized GNOME 46 Linux distribution derived
from Ubuntu 24.04 LTS (Noble).

Companion artefact to the Bachelor's thesis *Design and Deployment of a
Customized Linux Operating System with Native AI Integration: Case of
Aïobi OS* (RN Yanis Axel DABO, Burkina Institute of Technology).

## What this repository is

This repository ships:

- A **chroot-time build pipeline** that composes on top of a base
  Aïobi ISO to produce the release-candidate image (numbered shell
  scripts + orchestrator + test harness).
- An **on-device terminal AI assistant** with a hybrid symbolic-
  neural engine — deterministic answers on well-known Linux
  failure modes in <10 ms, LLM fallback on novel queries.
- A **native update mechanism** that replaces Ubuntu's GUI update
  stack with an Aïobi-branded, PolicyKit-authenticated one.
- A **first-boot debloat service** that removes the Ubuntu
  telemetry packages retained during install to let Subiquity work.
- **Brand defaults enforced at the system level** via dconf
  keyfiles, with user-freedom carve-outs on colour scheme,
  wallpaper, and accent.
- A **kernel-level zero-data-leak posture** for the on-device AI —
  Ollama loopback bind + iptables OUTPUT filter.
- **Architecture UMLs** backing the thesis chapters.

Scripts run inside a **Cubic chroot** during ISO build (on top of a
prior Aïobi base ISO carrying the identity + branding layer), and
are also safe to re-run on an installed VM.

## Repository layout

```
aiobi-os-core/
├── README.md
├── LICENSE
├── SECURITY.md
├── scripts/          # 22 numbered chroot scripts + run-all.sh + validate.sh + tests/
├── aiobi-term/       # terminal AI assistant (CLI + Python package + readline)
├── aiobi-update/     # native update mechanism (CLI + systemd units + polkit + apt hooks)
├── config/           # dconf profile + keyfiles + local.d/
├── design/           # architecture UMLs
├── icons/            # AI-native SVG placeholders
└── aiobi-theme/      # legacy overlay stylesheets (superseded by script 03)
```

Detailed file layouts live in the per-subtree READMEs.

## Usage

### Inside a Cubic chroot (ISO build)

```bash
scp -r aiobi-os-core/ <chroot-host>:/tmp/
cd /tmp/aiobi-os-core
bash scripts/run-all.sh
```

`run-all.sh` chains every step in the correct dependency order and
runs `validate.sh` at the end.

### On an installed VM (post-install polish)

Same commands. Scripts detect the presence of an active D-Bus session
and adapt (live extension enablement, per-user dconf writes).

## AI layer

Two consumers share a single locally-bound Ollama daemon:

| Consumer                | Model tag                              | Role                                              |
|-------------------------|----------------------------------------|---------------------------------------------------|
| `aiobi-term` (terminal) | `qwen2.5:1.5b`                         | Chat + shell-command extraction                   |
| AnythingLLM (desktop)   | `qwen3-vl:2b-instruct-q8_0`            | Multi-modal chat (text + image)                   |

Both models ship in the ISO (~3.4 GB of the total image size) so the
on-device AI is available at first login without network access —
an air-gapped install has full AI capability from the first user
session. Script `15-install-ollama.sh` pulls them during the chroot
build via a manually-started `ollama serve` process, then Cubic
Generate captures `/usr/share/ollama/.ollama/models/` into the ISO
squashfs. A defensive `aiobi-ollama-firstpull.service` is registered
as a fallback that only activates on the edge case where the
chroot-time pull did not complete (marker file
`/var/lib/aiobi-ollama-firstpull-done` is touched on successful
chroot pull to skip it on the installed system). The daemon is
socket-activated via `systemd-socket-proxyd` on `127.0.0.1:11434`
→ `127.0.0.1:11435` and unloads models after `OLLAMA_KEEP_ALIVE=5m`
of idleness — zero resident memory when idle.

## System maintenance

`aiobi-update` is the sole update surface on the installed system;
Ubuntu's `update-manager` / `update-notifier` / `software-properties-gtk`
are purged by script `23-install-aiobi-update.sh` and pinned at `-10`
so they cannot be reinstalled by dependency chain.

- **Weekly check** — `aiobi-update.timer` fires Sunday 06:00
  (`RandomizedDelaySec=1h`), runs `apt-get update -qq`, writes
  `/var/lib/aiobi-update/state.json`, and touches a notify trigger.
- **Daily security auto-apply** — `aiobi-update-security.timer` fires
  daily 03:00, runs `aiobi-update --apply --security-only -y`.
- **Interactive apply** — `aiobi-update --apply` (no sudo) shows a
  GTK confirm popup, then `pkexec` opens a PolicyKit dialog for the
  admin password before the `apt` subprocess runs. Kernel updates
  install normally and surface via the `/var/run/reboot-required`
  notification.

## First-boot provisioning

`snapd` is intentionally kept in the ISO so Subiquity (which is a
snap) can run installation. `aos-debloat.service` (installed by
`10-snap-final-purge.sh`) is a systemd oneshot that runs once at
first boot on the installed system, purges `snapd` plus five
telemetry companions (`ubuntu-report`, `popularity-contest`, `apport`,
`whoopsie`, `apport-symptoms`), then disables and unlinks itself.
The Live-CD path is skipped via a `df -T /` overlay guard.

## Design tokens

| Token             | Value       | Role                              |
|-------------------|-------------|-----------------------------------|
| `aio-black`       | `#0F1010`   | Primary background                |
| `aio-white`       | `#F8F8F9`   | Primary foreground                |
| `aio-violet`      | `#7233CD`   | Primary accent                    |
| `aio-violet-700`  | `#5C24A8`   | Press / active                    |
| `aio-violet-300`  | `#B593E4`   | Hover / disabled                  |

## Locked vs unlocked settings

`06-apply-persistence.sh` installs dconf locks on brand-critical keys
and leaves user-freedom keys unlocked.

| Key                                             | Status    | Reason                |
|-------------------------------------------------|-----------|-----------------------|
| `gtk-theme` / `icon-theme` / `font-name`        | LOCKED    | brand-critical        |
| `monospace-font-name`                           | LOCKED    | brand-critical        |
| `enabled-extensions` / `disabled-extensions`    | LOCKED    | dock layout integrity |
| `color-scheme` (light / dark)                   | UNLOCKED  | user freedom          |
| `picture-uri` (wallpaper)                       | UNLOCKED  | user freedom          |
| `accent-color`                                  | UNLOCKED  | user freedom          |

Every script is idempotent — it backs up any file it modifies on
first run and restores from the backup before re-applying on
subsequent runs.

## References

- freedesktop.org `os-release` specification
- Debian `dpkg-divert(1)` man page
- GNOME administrator guide (dconf profiles, keyfiles, lockdown)
- Ubuntu Yaru community theme, Papirus icon theme upstream
- Cubic — Custom Ubuntu ISO Creator

## License

MIT — see `LICENSE`.
