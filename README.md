# aiobi-os-core

Reproducible customization pipeline for **Aïobi OS**, a customized Linux
distribution derived from Ubuntu 24.04 LTS (Noble) with GNOME 46. This
repository contains the scripts, configuration files, and asset stubs
that transform a stock Ubuntu ISO into an Aïobi OS ISO.

Companion artefact to the Bachelor's thesis *Design and Deployment of a
Customized Linux Operating System with Native AI Integration: Case of
Aïobi OS* (RN Yanis Axel DABO, Burkina Institute of Technology).

## What this repository is

- **15 idempotent shell scripts** that apply the five customization
  layers (system identity, visual identity, shell composition,
  application inventory, persistence & lockdown) plus a validation
  script and an all-in-one orchestrator.
- **`dconf` keyfiles and profile** that enforce brand defaults at the
  system level while preserving user freedom on non-negotiable keys
  (colour scheme, wallpaper, accent).
- **SVG icon placeholders** for the AI-native surface (chat, terminal,
  status indicators) awaiting their production art pass.
- **`config/local.d/`** overrides installed under
  `/etc/dconf/db/local.d/` at deploy time.

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
│   ├── 04b-override-icons.sh       # Later-sprint icon swap
│   ├── 05-rebrand-os.sh            # OS identity + GRUB + MOTD + first-boot service
│   ├── 06-apply-persistence.sh     # dconf profile + locks + skel + fonts
│   ├── 07-validate-us14.sh         # PASS/FAIL check against milestone criteria
│   ├── 08-inject-shell-theme.sh    # GNOME Shell theme (Yaru clone + sed)
│   ├── 09-terminal-profile.sh      # GNOME Terminal palette
│   ├── 10-snap-final-purge.sh      # snap removal + APT pin
│   ├── 11-apt-brand-alias.sh       # /etc/hosts + DEB822 mirror alias
│   ├── 12-wine-proton-install.sh   # Wine 9.0 + GE-Proton + MIME handlers
│   ├── 13-productivity-stack.sh    # OnlyOffice + Brave + VLC + Flameshot + Flatpaks
│   └── 14-day5-polish-all.sh       # orchestrator (chains 01–13 + 07)
├── config/
│   ├── dconf-profile               # /etc/dconf/profile/user
│   ├── aiobi-panel.dconf           # /etc/dconf/db/local.d/20-aiobi-panel
│   └── local.d/
│       └── 00-aiobi-branding       # gtk/icon/font system defaults
├── aiobi-theme/                    # legacy overlay stylesheets (V1, superseded by 03)
└── icons/                          # AI-native SVG placeholders
```

## Usage

### Inside a Cubic chroot (ISO build)

```bash
# 1. Copy the repository into the chroot (any writable path).
scp -r aiobi-os-core/ <chroot-host>:/tmp/

# 2. Open the Cubic terminal (root inside the chroot).
cd /tmp/aiobi-os-core

# 3. Recommended --- one-shot orchestrator (runs all layers + validation):
bash scripts/14-day5-polish-all.sh

# Or run individually, in this order:
bash scripts/01-install-extensions.sh
bash scripts/02-configure-panel.sh
bash scripts/03-inject-theme.sh
bash scripts/04-install-icons.sh
bash scripts/05-rebrand-os.sh
bash scripts/08-inject-shell-theme.sh
bash scripts/09-terminal-profile.sh
bash scripts/10-snap-final-purge.sh
bash scripts/11-apt-brand-alias.sh
bash scripts/12-wine-proton-install.sh
bash scripts/13-productivity-stack.sh
bash scripts/06-apply-persistence.sh
bash scripts/07-validate-us14.sh
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
