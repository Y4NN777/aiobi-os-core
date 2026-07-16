# config/base-iso — assets consumed by scripts/base-iso/

The baseline scripts do **not** carry binary assets in the repository. They
read PNGs from a staging location inside the Cubic chroot, defaulting to
`/root/aiobi-base-assets/`. This directory documents the expected layout
so the assets can be assembled once and re-staged into every fresh chroot.

## Expected inventory

```
/root/aiobi-base-assets/
├── aiobi_os_grub.png                    # 1024x768 PNG, GRUB background
├── plymouth-aiobi/
│   ├── background.png                   # 1024x768 Aïobi black #0F1010
│   ├── watermark.png                    # transparent, white Aïobi logo
│   ├── entry.png                        # violet #4A3C5C LUKS entry raster
│   └── throbber-0001.png .. throbber-0036.png  (200x200 transparent frames)
└── gdm/
    ├── aiobi_gdm_background.png         # GDM greeter background (Figma)
    └── aiobi_gdm_avatar.png             # centred avatar, 256x256+
```

## Overrides

Each consuming script accepts an environment-variable override so an
alternate staging path can be used:

- `AIOBI_ASSETS_DIR` — root of the Plymouth assets (default:
  `/root/aiobi-base-assets/plymouth-aiobi`).
- `AIOBI_GRUB_BG` — full path to the GRUB PNG (default:
  `/root/aiobi-base-assets/aiobi_os_grub.png`).
- `AIOBI_GDM_ASSETS` — directory containing the two GDM PNGs (default:
  `/root/aiobi-base-assets/gdm`).

## Source of truth

The canonical Figma exports live in the design brief; committed copies (if
any) belong under this directory tree once approved. Placing raster assets
under `plymouth-aiobi/` and `gdm/` here is safe — the scripts will pick them
up via `AIOBI_*` env vars pointing at
`.../aiobi-os-core/config/base-iso/{plymouth-aiobi,gdm}` if you prefer to
build directly from the repo rather than from a chroot staging copy.
