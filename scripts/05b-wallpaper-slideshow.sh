#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Step 05b — Wallpaper slideshow manifest generation
# =============================================================================
# Purpose : generate /usr/share/backgrounds/aiobi/aiobi-slideshow.xml from
#           every PNG present at /usr/share/backgrounds/aiobi/, so the
#           GNOME wallpaper crossfades through the Aïobi brand image set
#           every 30 min instead of remaining fixed on a single image.
#
# Format  : GNOME's native XML slideshow schema (documented since
#           gnome-shell 3.x, still current in GNOME 46). A <background>
#           root wraps alternating <static> (image displayed) and
#           <transition> (crossfade to next) blocks. The last transition
#           wraps back to the first image so the cycle is infinite. No
#           third-party wallpaper changer needed — the compositor
#           renders the crossfade natively.
#
# Timing  : each image displays for 1255 s (~21 min) then a 5 s crossfade
#           bridges to the next → 21 min per wallpaper, N × 21 min for
#           one full loop. 20 assets → 7 h full loop (user preference:
#           30 min per slide = 10 h loop was too long, 3 min per slide
#           was too short, 21 min lands the full loop at 7 h — enough
#           transitions in a work day to feel dynamic without the
#           wallpaper changing distractingly often).
#
# The referenced XML is consumed by config/aiobi-wallpaper.dconf which
# script 06 installs as /etc/dconf/db/local.d/00-aiobi-wallpaper. If
# fewer than 2 PNGs are present the script degrades gracefully to a
# single-image manifest (no crossfade — GNOME still accepts it).
#
# Ordering: must run BEFORE 06-apply-persistence.sh so the XML exists
# on disk when the dconf keyfile referencing it is compiled.
#
# Idempotent: overwrites the XML every run. Safe to re-run after adding
# or removing a PNG in the backgrounds directory.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

BG_DIR=/usr/share/backgrounds/aiobi
XML_OUT="$BG_DIR/aiobi-slideshow.xml"

echo "==> Aïobi — 05b-wallpaper-slideshow.sh"

if [ ! -d "$BG_DIR" ]; then
    echo "  SKIP — $BG_DIR does not exist (no Aïobi wallpaper assets to slideshow)"
    exit 0
fi

# Collect the PNGs, sorted so the sequence is deterministic across reruns.
# Excludes the generated aiobi-slideshow.xml and any *.bak we might leave.
mapfile -t PNGS < <(find "$BG_DIR" -maxdepth 1 -type f -iname "*.png" | sort)
N=${#PNGS[@]}

if [ "$N" -eq 0 ]; then
    echo "  SKIP — no PNG files found under $BG_DIR"
    exit 0
fi

echo "  found $N wallpaper(s), generating slideshow manifest..."

# Write the XML manifest.
{
    printf '<background>\n'
    printf '  <starttime>\n'
    printf '    <year>2026</year>\n'
    printf '    <month>01</month>\n'
    printf '    <day>01</day>\n'
    printf '    <hour>00</hour>\n'
    printf '    <minute>00</minute>\n'
    printf '    <second>00</second>\n'
    printf '  </starttime>\n'

    if [ "$N" -eq 1 ]; then
        # Single image — no transition needed, GNOME will just display it.
        printf '  <static>\n'
        printf '    <duration>86400.0</duration>\n'
        printf '    <file>%s</file>\n' "${PNGS[0]}"
        printf '  </static>\n'
    else
        for i in "${!PNGS[@]}"; do
            current="${PNGS[$i]}"
            next="${PNGS[$(( (i + 1) % N ))]}"
            printf '  <static>\n'
            printf '    <duration>1255.0</duration>\n'
            printf '    <file>%s</file>\n' "$current"
            printf '  </static>\n'
            printf '  <transition type="overlay">\n'
            printf '    <duration>5.0</duration>\n'
            printf '    <from>%s</from>\n' "$current"
            printf '    <to>%s</to>\n' "$next"
            printf '  </transition>\n'
        done
    fi

    printf '</background>\n'
} > "$XML_OUT"

chmod 0644 "$XML_OUT"

echo "==> 05b done — $XML_OUT written ($N image(s), 30 min per slide, 5 s crossfade)"
echo "    Effect on installed VM: desktop + lock screen crossfade through"
echo "    all Aïobi wallpapers on a $((N * 30 / 60)) h $((N * 30 % 60)) min loop."
