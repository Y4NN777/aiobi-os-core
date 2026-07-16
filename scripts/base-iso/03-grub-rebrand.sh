#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Base ISO — Step 03 — GRUB rebrand (background + safety resolution)
# =============================================================================
# WHAT
#   1. Deploys the Aïobi GRUB background PNG under /boot/grub/.
#   2. Configures /etc/default/grub with the Aïobi distributor name, the
#      background path, and a hardware-safe 1024x768 gfx mode.
#   3. Applies the Anti-Casse dpkg-divert on the vendor
#      /usr/share/images/desktop-base/desktop-grub.png slot so future
#      grub-common / desktop-base updates cannot revert our background.
#   4. Runs update-grub to rebuild /boot/grub/grub.cfg.
#
# WHY GRUB_DISTRIBUTOR
#   The distributor name is what appears in the "Advanced options for X"
#   sub-menu and in the fallback boot entries. Pinning it here breaks the
#   last visible surface where "Ubuntu" would leak into the bootloader.
#
# WHY 1024x768
#   Hardware-safe resolution present on every UEFI GOP + legacy VBE mode
#   table. Higher modes require GRUB to detect the VBE cube at boot; if
#   detection fails GRUB falls back to text mode and the background never
#   renders. 1024x768 with `,auto` fallback covers both cases.
#
# WHY dpkg-divert
#   The desktop-base package ships its own desktop-grub.png and hooks it
#   into GRUB's background probe on install. A `dpkg-divert --local
#   --rename --add` on that path preserves the vendor original at
#   `desktop-grub.png.distrib` and lets our /boot/grub/aiobi_grub.png win
#   at every subsequent update.
#
# ASSETS
#   Expected at /root/aiobi-base-assets/aiobi_os_grub.png (1024x768 PNG).
#   Override with AIOBI_GRUB_BG env var.
#
# SOURCES
#   - https://help.ubuntu.com/community/Grub2/Displays
#   - https://manpages.ubuntu.com/manpages/noble/en/man8/update-grub.8.html
#   - https://manpages.ubuntu.com/manpages/noble/en/man1/dpkg-divert.1.html
#
# IDEMPOTENT: dpkg-divert --add is a no-op if the diversion already exists
#   (the script checks with --list first); the sed patterns are anchored so
#   re-running does not duplicate the GRUB_BACKGROUND line.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

GRUB_BG_SRC="${AIOBI_GRUB_BG:-/root/aiobi-base-assets/aiobi_os_grub.png}"
GRUB_BG_DST="/boot/grub/aiobi_grub.png"
VENDOR_ASSET="/usr/share/images/desktop-base/desktop-grub.png"

echo "==> Aïobi — 03-grub-rebrand.sh"

# ----- 1) Deploy the background --------------------------------------------
if [ ! -f "$GRUB_BG_SRC" ]; then
    echo "  ERROR: $GRUB_BG_SRC not found — stage the Aïobi GRUB PNG before running,"
    echo "         or set AIOBI_GRUB_BG."
    exit 1
fi

mkdir -p /boot/grub
cp "$GRUB_BG_SRC" "$GRUB_BG_DST"
chmod 644 "$GRUB_BG_DST"
echo "  installed $GRUB_BG_DST"

# ----- 2) /etc/default/grub — distributor, background, gfx mode -------------
# GRUB_DISTRIBUTOR is normally a shell one-liner that lsb_release'd out to
# "Ubuntu"; pin it to a literal string so no external command decides the
# name at update-grub time.
echo "  pinning GRUB_DISTRIBUTOR + background + gfx mode in /etc/default/grub"

# Distributor
if grep -qE '^GRUB_DISTRIBUTOR=' /etc/default/grub; then
    sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="Aïobi OS"|' /etc/default/grub
else
    echo 'GRUB_DISTRIBUTOR="Aïobi OS"' >> /etc/default/grub
fi

# Background — remove any prior GRUB_BACKGROUND line, then append ours
sed -i '/^GRUB_BACKGROUND=/d' /etc/default/grub
echo "GRUB_BACKGROUND=\"$GRUB_BG_DST\"" >> /etc/default/grub

# Gfx mode — enable the previously-commented default and set 1024x768,auto
sed -i 's|^#\?GRUB_GFXMODE=.*|GRUB_GFXMODE=1024x768,auto|' /etc/default/grub
grep -qE '^GRUB_GFXMODE=' /etc/default/grub || \
    echo 'GRUB_GFXMODE=1024x768,auto' >> /etc/default/grub

# ----- 3) Anti-Casse — divert the vendor GRUB background asset --------------
if ! dpkg-divert --list | grep -q " $VENDOR_ASSET$"; then
    echo "  registering dpkg-divert on $VENDOR_ASSET"
    dpkg-divert --local --rename --add "$VENDOR_ASSET"
else
    echo "  dpkg-divert on $VENDOR_ASSET already registered — skip"
fi

# If the vendor asset slot exists (empty after divert), symlink our PNG so
# any consumer that opens the vendor path also gets the Aïobi visual.
mkdir -p "$(dirname "$VENDOR_ASSET")"
ln -sf "$GRUB_BG_DST" "$VENDOR_ASSET"

# ----- 4) Rebuild grub.cfg --------------------------------------------------
echo "  running update-grub"
update-grub

# ----- 5) Verification -------------------------------------------------------
echo
echo "  Verification:"
printf "    GRUB_DISTRIBUTOR = "; grep -E '^GRUB_DISTRIBUTOR=' /etc/default/grub
printf "    GRUB_BACKGROUND  = "; grep -E '^GRUB_BACKGROUND='  /etc/default/grub
printf "    GRUB_GFXMODE     = "; grep -E '^GRUB_GFXMODE='     /etc/default/grub
printf "    dpkg-divert      = "; dpkg-divert --list | grep -c "$VENDOR_ASSET" || true

echo "==> 03 done"
