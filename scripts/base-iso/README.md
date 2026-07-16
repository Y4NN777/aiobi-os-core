# base-iso — Aïobi OS baseline construction

These scripts build the **Aïobi OS baseline ISO** from a stock Ubuntu 24.04
(Noble Numbat) desktop ISO inside a Cubic chroot session. They cover every
step from the pristine Canonical image up to the point where the top-level
`../*.sh` scripts take over to compose the final release ISO on top.

The baseline ships the load-bearing brand and persistence layers:

- **Bootloader identity** — GRUB rebrand with Aïobi background pinned via
  `dpkg-divert` on the vendor `desktop-grub.png` slot.
- **Splash & LUKS UI** — custom Plymouth `two-step` theme with 36-frame
  central throbber, violet entry border, transparent minimalist anchors,
  baked into the initial ramdisk via `update-initramfs -u -v`.
- **GDM greeter** — full extraction of the Yaru `gnome-shell-theme.gresource`,
  Aïobi background + avatar PNGs injected into the resource tree, `gdm.css`
  overrides for the password entry and the fallback-symbolic-icon overlay,
  Ubuntu logo container collapsed, recompiled binary reinstalled via
  `dpkg-divert` on the canonical Yaru path.
- **User templates** — the `${HOME}/.face` linkage in the AccountsService
  administrator + standard templates is severed via `dpkg-divert`, and
  `gnome-initial-setup` is configured to skip the account/avatar page.
- **Session labels** — the four Ubuntu `.desktop` session files
  (Xorg + Wayland variants) are renamed to `Aïobi OS` with the `ï`
  reconstructed from its UTF-8 bytes `0xc3 0xaf` via `printf` to bypass
  heredoc encoding round-trips, each pinned via `dpkg-divert`.

## Prerequisites

- Cubic session opened on a stock `ubuntu-24.04-desktop-amd64.iso`.
- The chroot terminal is active (Cubic "Terminal" tab).
- The `config/base-iso/plymouth-aiobi/` assets (background, avatar, entry,
  throbber-000{1..36}.png) have been staged into the chroot at
  `/root/aiobi-base-assets/` — the scripts copy from that path.
- Free space in the chroot: at least 500 MB for the GDM build tree
  (`/aiobi-gdm-build`).

## Execution order

Run either the orchestrator or the individual scripts in numeric order:

```bash
sudo ./00-run-all-base.sh
```

or, one by one:

```bash
sudo ./01-chroot-preflight.sh
sudo ./02-plymouth-install.sh
sudo ./03-grub-rebrand.sh
sudo ./04-gdm-branding.sh
sudo ./05-accountsservice-templates.sh
sudo ./06-sessions-rename-divert.sh
```

Once the baseline is applied, exit the chroot, generate the intermediate ISO
via Cubic's "Generate" step, then use that ISO as the Cubic base for the
top-level `../scripts/*.sh` composition pipeline.

## Overlap with the composition pipeline

Deliberately **not** included here (already covered by the top-level scripts):

- `../scripts/05-rebrand-os.sh` — `/etc/os-release`, `/etc/lsb-release`, issue
  banners.
- `../scripts/10-snap-final-purge.sh` — snap purge, APT pin, and the
  self-destructing `aos-debloat.service` first-boot unit.
- `../scripts/11-apt-brand-alias.sh` — APT mirror rebrand.

Running the baseline scripts on top of a stock ISO produces the RC1-equivalent
input that the top-level pipeline is designed to consume.
