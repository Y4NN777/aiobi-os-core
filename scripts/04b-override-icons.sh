#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Step 04b — Override placeholders with the final Aïobi icon set
# =============================================================================
# WHAT
#   When delivers the final Aïobi icon SVGsin a later iteration, drop them into
#   ./icons-sprint2/ (same filenames as the 5 placeholders from script 04):
#     - aiobi-start-menu.svg
#     - aiobi-ai-terminal.svg
#     - aiobi-ai-chat.svg
#     - aiobi-ai-secure-status.svg
#     - aiobi-firewall-status.svg
#   Then run this script. It:
#     1. Validates every expected file is present (fail fast — no half install).
#     2. Backs up the Sprint-1 placeholders to /usr/share/icons/Aiobi.sprint1.bak/.
#     3. Copies the new SVGs into /usr/share/icons/Aiobi/scalable/apps/.
#     4. Re-rasters PNGs at Freedesktop standard sizes.
#     5. Refreshes the icon cache.
#
# WHY a separate script
#   later-iteration should not require re-running 04 (which would re-audit + re-sed
#   Papirus — slow and unnecessary). 04b is the surgical update path:
#   placeholder-only swap, no Papirus touch.
#
# IDEMPOTENT: re-running re-installs from icons-sprint2/ if present;
#   the Sprint-1 backup is preserved on first run only.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${KALEB_SVG_DIR:-$HERE/icons-sprint2}"
DEST_DIR="/usr/share/icons/Aiobi"
SPRINT1_BAK="/usr/share/icons/Aiobi.sprint1.bak"

EXPECTED=(
    aiobi-start-menu.svg
    aiobi-ai-terminal.svg
    aiobi-ai-chat.svg
    aiobi-ai-secure-status.svg
    aiobi-firewall-status.svg
)

echo "==> Aïobi — 04b-override-icons.sh"
echo "  source: $SRC_DIR"

[ -d "$SRC_DIR" ] || { echo "ERROR: $SRC_DIR missing — drop the final SVGs there first"; exit 1; }
[ -d "$DEST_DIR" ] || { echo "ERROR: $DEST_DIR missing — run script 04 first"; exit 1; }

# Validate all expected files are present before any write
missing=()
for f in "${EXPECTED[@]}"; do
    [ -f "$SRC_DIR/$f" ] || missing+=("$f")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "ERROR: missing in $SRC_DIR:"
    printf "  %s\n" "${missing[@]}"
    exit 1
fi

# Back up Sprint-1 placeholders on first run only
if [ ! -d "$SPRINT1_BAK" ]; then
    cp -a "$DEST_DIR" "$SPRINT1_BAK"
    echo "  initial backup → $SPRINT1_BAK"
fi

# Swap SVGs
install -m 0644 "$SRC_DIR"/aiobi-*.svg "$DEST_DIR/scalable/apps/"
echo "  installed ${#EXPECTED[@]} SVGs"

# Re-raster PNGs at standard sizes
if command -v rsvg-convert >/dev/null 2>&1; then
    for size in 16 22 24 32 48 64 128 256; do
        out="$DEST_DIR/${size}x${size}/apps"
        mkdir -p "$out"
        for svg in "$DEST_DIR/scalable/apps"/aiobi-*.svg; do
            name=$(basename "$svg" .svg)
            rsvg-convert -w $size -h $size "$svg" -o "$out/$name.png" 2>/dev/null || true
        done
    done
    echo "  rasterised PNG at 16/22/24/32/48/64/128/256 px"
fi

gtk-update-icon-cache -f -t "$DEST_DIR" 2>/dev/null || true

echo "==> 04b done — Aïobi icon theme now uses Sprint-2 assets"
