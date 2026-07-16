#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Base ISO — Step 02 — Plymouth theme install + initramfs bake
# =============================================================================
# WHAT
#   Deploys the Aïobi Plymouth theme under
#   /usr/share/plymouth/themes/aiobi/, registers it as the default theme
#   via `update-alternatives`, and rebuilds the initial ramdisk so the
#   theme is available at the earliest boot stage (before rootfs mount and
#   at the LUKS decryption prompt).
#
# WHY
#   Plymouth is invoked from initramfs before /usr is mounted, so the theme
#   assets and configuration must be baked into the ramdisk itself — the
#   root filesystem symlink from `update-alternatives` is not enough.
#   Running `update-initramfs -u -v` after `update-alternatives --set`
#   embeds the 36-frame throbber, the violet entry border, and the four
#   transparent anchor PNGs directly into /boot/initrd.img-*.
#
# WHY the "invisible anchor" architecture
#   The Plymouth `two-step` C-module enforces a hardcoded asset manifest
#   (splash.png, logo.png, lock.png). Removing them causes the module to
#   panic and fall back to text mode. We satisfy the manifest with 1x1
#   transparent PNGs so the module renders nothing where the default
#   padlock / distributor logo would appear, leaving only the Aïobi
#   throbber + violet LUKS entry visible.
#
# ASSETS
#   Sourced from $HERE/config/base-iso/plymouth-aiobi/ (relative to the
#   repository root). Expected inventory:
#     - background.png    (1024x768, Aïobi black #0F1010)
#     - watermark.png     (transparent, white Aïobi logo)
#     - entry.png         (violet #4A3C5C border raster)
#     - throbber-0001.png .. throbber-0036.png (200x200 transparent frames)
#   Staged into the chroot at /root/aiobi-base-assets/plymouth-aiobi/
#   before Cubic launches this script.
#
# SOURCES
#   - https://www.freedesktop.org/wiki/Software/Plymouth/
#   - man 5 plymouth-theme
#   - https://manpages.ubuntu.com/manpages/noble/en/man8/update-initramfs.8.html
#
# IDEMPOTENT: mkdir/cp are safe; update-alternatives --install with a fixed
#   priority is idempotent; update-initramfs -u overwrites.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

HERE="$(cd "$(dirname "$0")/../.." && pwd)"
ASSETS_SRC="${AIOBI_ASSETS_DIR:-/root/aiobi-base-assets/plymouth-aiobi}"
THEME_DIR="/usr/share/plymouth/themes/aiobi"

echo "==> Aïobi — 02-plymouth-install.sh"

# ----- 1) Dependencies -------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get install -y plymouth plymouth-themes initramfs-tools

# ----- 2) Theme directory + shared functional assets from spinner -----------
echo "  creating $THEME_DIR"
mkdir -p "$THEME_DIR"

# Keep the functional icons from the upstream spinner theme (bullet,
# keyboard, capslock) — the two-step module requires them to render
# password-entry feedback. Removing them would trigger the C-module's
# text-mode fallback.
for asset in bullet.png keyboard.png capslock.png; do
    src="/usr/share/plymouth/themes/spinner/$asset"
    if [ -f "$src" ]; then
        cp "$src" "$THEME_DIR/$asset"
    else
        echo "  WARN: spinner asset $asset missing — theme may fall back to text mode"
    fi
done

# ----- 3) Aïobi-specific assets (Figma exports) -----------------------------
if [ ! -d "$ASSETS_SRC" ]; then
    echo "  WARN: $ASSETS_SRC missing — placeholder assets required."
    echo "        Stage the Aïobi Plymouth assets at $ASSETS_SRC before running,"
    echo "        or set AIOBI_ASSETS_DIR to point at the staged location."
    exit 1
fi

echo "  copying Aïobi assets from $ASSETS_SRC"
cp "$ASSETS_SRC"/throbber-*.png "$THEME_DIR/"
[ -f "$ASSETS_SRC/entry.png" ]     && cp "$ASSETS_SRC/entry.png"     "$THEME_DIR/entry.png"
[ -f "$ASSETS_SRC/watermark.png" ] && cp "$ASSETS_SRC/watermark.png" "$THEME_DIR/watermark.png"
[ -f "$ASSETS_SRC/background.png" ] && cp "$ASSETS_SRC/background.png" "$THEME_DIR/background.png"

# ----- 4) Invisible anchor (1x1 transparent PNG) ----------------------------
# Base64-encoded 1x1 transparent PNG — deterministic, no external asset
# needed. Overrides the module's hardcoded splash.png / logo.png / lock.png
# so the default distributor logo and padlock never render.
echo "  writing invisible anchor for splash.png / logo.png / lock.png"
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" \
    | base64 -d > "$THEME_DIR/transparent.png"
cp "$THEME_DIR/transparent.png" "$THEME_DIR/splash.png"
cp "$THEME_DIR/transparent.png" "$THEME_DIR/logo.png"
cp "$THEME_DIR/transparent.png" "$THEME_DIR/lock.png"

# ----- 5) Theme configuration file ------------------------------------------
# Brand colours in the 0xRRGGBB form the Plymouth daemon parses:
#   Primary Black     #0F1010
#   Support Violet    #4A3C5C
#   Primary White     #F8F8F9
# Watermark alignment (0.5, 0.35) provides visual breathing room above
# the LUKS entry.
echo "  writing $THEME_DIR/aiobi.plymouth"
cat > "$THEME_DIR/aiobi.plymouth" << 'EOF'
[Plymouth Theme]
Name=Aïobi
Description=Official Aïobi OS Boot Theme
ModuleName=two-step

[two-step]
ImageDir=/usr/share/plymouth/themes/aiobi
HorizontalAlignment=0.5
VerticalAlignment=0.5
Transition=none
TransitionDuration=0.0

# Brand background (Primary Black #0F1010)
BackgroundColor=0x0F1010
BackgroundStartColor=0x0F1010
BackgroundEndColor=0x0F1010

# Watermark placement — leaves breathing room above the LUKS entry
WatermarkHorizontalAlignment=0.5
WatermarkVerticalAlignment=0.35

# Typography colours (Support Violet #4A3C5C)
TitleColor=0x4A3C5C
PromptColor=0x4A3C5C
DialogCleuColor=0x4A3C5C
DialogActiveColor=0xF8F8F9
EOF

# ----- 6) Register as default alternative + activate ------------------------
echo "  registering aiobi as default Plymouth theme"
update-alternatives --install \
    /usr/share/plymouth/themes/default.plymouth default.plymouth \
    "$THEME_DIR/aiobi.plymouth" 200
update-alternatives --set default.plymouth "$THEME_DIR/aiobi.plymouth"

# ----- 7) Bake into initramfs -----------------------------------------------
# Deep verbose rebuild — the -v flag surfaces which theme files are being
# embedded, useful for post-run audit.
echo "  rebuilding initial ramdisk (this can take 20-60s)"
update-initramfs -u -v | grep -E "(plymouth|aiobi)" || true

# ----- 8) Verification -------------------------------------------------------
echo
echo "  Verification:"
printf "    default.plymouth -> "
readlink /usr/share/plymouth/themes/default.plymouth || echo "(unset)"
printf "    theme files count = "
find "$THEME_DIR" -type f | wc -l

echo "==> 02 done"
