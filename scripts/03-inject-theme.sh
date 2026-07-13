#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — US-1.4 / Step 03 — Inject Aïobi GTK theme (V2 REWRITE Day 5)
# =============================================================================
# WHAT (Day 5 REWRITE)
#   Ships /usr/share/themes/Aiobi/ as a FULL CLONE of Yaru-magenta-dark
#   with the primary Yaru magenta hex #B34CB3 sed-replaced by Aïobi violet
#   #7233CD. Both the loose CSS files (gtk-3.0/gtk.css, gtk-4.0/gtk.css)
#   AND the compiled gtk.gresource bundles are patched.
#
# WHY REWRITE (regression from Day 4 V1)
#   Day 4 V1 shipped an OVERLAY approach: /usr/share/themes/Aiobi/gtk-3.0/
#   contained ~30 selectors that ASSUMED Adwaita would fill missing rules
#   under the hood. This works for libadwaita GTK4 (@define-color overrides
#   Adwaita's baked stylesheet), but is STRUCTURALLY WRONG for GTK3 —
#   GTK3 loads exactly the CSS in /usr/share/themes/<name>/gtk-3.0/gtk.css
#   and applies CSS defaults (transparent!) for any undefined selector.
#   Result at first boot QA: every GTK3 app (Rhythmbox, LibreOffice,
#   Terminal, Image Viewer) rendered with transparent window backgrounds,
#   collapsed header bars, invisible menus.
#
#   V2 fix: clone Yaru's FULL theme tree (~3000 lines of complete CSS +
#   all assets) and inject Aïobi accent via sed. Costs code volume but
#   gains behavioural completeness.
#
# GRESOURCE PATCH (Day 5 §2.5 pattern)
#   Yaru also ships gtk.gresource (compiled binary bundle) containing
#   additional embedded CSS + SVG symbolics + PNG raster assets that
#   GTK3/4 loads in parallel to the on-disk CSS. Text sed doesn't touch
#   binary — we extract every entry, sed CSS + SVG entries only (PNG
#   rasters cannot be sed-recolored, documented V1.1 limitation),
#   regenerate manifest, glib-compile-resources, install.
#
# WHY internal resource prefix preserved
#   The gresource entries are namespaced /com/ubuntu/themes/Yaru-magenta-
#   dark/{3.0,4.0}/... and remain so after our recompile — we do NOT
#   rename to /com/aiobi/themes/Aiobi/. The CSS inside the bundle refers
#   to its own assets via relative resource URIs; renaming the prefix
#   would break every @import inside the bundle. GTK loads a gresource
#   by its FILE PATH (/usr/share/themes/Aiobi/gtk-{3,4}.0/gtk.gresource)
#   and the internal prefix is a private detail of that file.
#
# REFERENCES
#   - Log 5 §2.4 (Bug A architecture correction, full-clone approach)
#   - Log 5 §2.5 (gresource extract/sed/recompile pipeline)
#   - Log 5 §4.1 (overlay-vs-full-theme lesson)
#   - Log 5 §4.2 (gresource pattern generalisation from Day 3 §2.0.2)
#   - Yaru accent-colors.scss.in: #B34CB3 magenta primary
#
# IDEMPOTENT: backup on first run + restore before every re-apply.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi US-1.4 / 03-inject-theme.sh (V2 Day 5)"

SRC_VARIANT=Yaru-magenta-dark
YARU_ROOT="/usr/share/themes/${SRC_VARIANT}"
AIOBI_ROOT="/usr/share/themes/Aiobi"

# Hex family map: Yaru magenta → Aïobi violet
# Primary Yaru magenta:      #B34CB3
# Aïobi Primary Violet:      #7233CD
# Yaru compile-time derivatives (from optimize-contrast()) may include a spread
# of magenta-family shades — sed catches the primary, PNG rasters remain
# magenta (V1.1 improvement: re-render from SVG source).

sed_hex_files() {
    local dir="$1"
    find "$dir" -type f \( -name "*.css" -o -name "*.svg" \) -exec sed -i \
        -e 's/#B34CB3/#7233CD/gI' \
        -e 's/rgb(179,\s*76,\s*179)/rgb(114, 51, 205)/g' \
        -e 's/rgba(179,\s*76,\s*179/rgba(114, 51, 205/g' \
        {} +
}

# ----- 1) Sanity — Yaru variant installed -----------------------------------
if [ ! -d "$YARU_ROOT" ]; then
    echo "ERROR: $YARU_ROOT not found. Install yaru-theme first:"
    echo "  apt-get install -y yaru-theme-gtk yaru-theme-icon yaru-theme-sound"
    exit 2
fi

# ----- 2) Backup previous Aïobi theme (idempotent restore path) --------------
if [ -d "$AIOBI_ROOT" ]; then
    if [ ! -d "${AIOBI_ROOT}.day5.bak" ]; then
        cp -r "$AIOBI_ROOT" "${AIOBI_ROOT}.day5.bak"
        echo "  backup → ${AIOBI_ROOT}.day5.bak"
    fi
    rm -rf "$AIOBI_ROOT"
fi

# ----- 3) Full clone Yaru-magenta-dark → Aïobi -------------------------------
mkdir -p "$AIOBI_ROOT"
# Only gtk-3.0, gtk-4.0, index.theme — skip gnome-shell which 08-inject-shell-theme.sh handles
for sub in gtk-3.0 gtk-4.0 index.theme; do
    if [ -e "$YARU_ROOT/$sub" ]; then
        cp -r "$YARU_ROOT/$sub" "$AIOBI_ROOT/"
    fi
done

# Fix index.theme Name field to say Aiobi
if [ -f "$AIOBI_ROOT/index.theme" ]; then
    sed -i 's/^Name=.*/Name=Aiobi/' "$AIOBI_ROOT/index.theme"
fi

echo "  cloned $SRC_VARIANT → Aiobi (gtk-3.0 + gtk-4.0)"

# ----- 4) Sed on-disk CSS files ---------------------------------------------
for tree in "$AIOBI_ROOT/gtk-3.0" "$AIOBI_ROOT/gtk-4.0"; do
    [ -d "$tree" ] && sed_hex_files "$tree"
done
echo "  sed applied to on-disk CSS/SVG"

# ----- 5) Gresource extract → sed → recompile (Day 3 §2.0.2 pattern) --------
process_gresource() {
    local version_dir="$1"    # /usr/share/themes/Aiobi/gtk-3.0 or gtk-4.0
    local gres_path="${version_dir}/gtk.gresource"
    [ -f "$gres_path" ] || return 0

    local gres_ver="${version_dir##*/gtk-}"   # "3.0" or "4.0"
    local res_prefix="/com/ubuntu/themes/${SRC_VARIANT}/${gres_ver}"
    local bak="${gres_path}.magenta.bak"
    local work="/tmp/aiobi-gres-work/${gres_ver}"

    echo "  processing gresource: $gres_path"
    # Backup on first run, restore-from-backup on subsequent runs (idempotent)
    if [ ! -f "$bak" ]; then
        cp "$gres_path" "$bak"
    else
        cp "$bak" "$gres_path"
    fi

    # Extract every entry
    mkdir -p "$work"
    rm -rf "${work:?}"/*
    mapfile -t entries < <(gresource list "$gres_path")
    for entry in "${entries[@]}"; do
        rel="${entry#$res_prefix/}"
        mkdir -p "$(dirname "$work/$rel")"
        gresource extract "$gres_path" "$entry" > "$work/$rel"
    done

    # Sed on the extracted CSS + SVG (PNG binaries left untouched — V1.1)
    sed_hex_files "$work"

    # Generate manifest preserving internal path prefix
    local manifest="$work/gtk.gresource.xml"
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<gresources>'
        echo "  <gresource prefix=\"${res_prefix}\">"
        for entry in "${entries[@]}"; do
            echo "    <file>${entry#$res_prefix/}</file>"
        done
        echo '  </gresource>'
        echo '</gresources>'
    } > "$manifest"

    # Compile
    ( cd "$work" && glib-compile-resources gtk.gresource.xml --target=gtk.gresource )

    # Install
    cp "$work/gtk.gresource" "$gres_path"

    # Verification
    local magenta_count violet_count
    magenta_count=$(gresource extract "$gres_path" "${res_prefix}/gtk-dark.css" 2>/dev/null | grep -c '#B34CB3' || echo 0)
    violet_count=$(gresource extract "$gres_path" "${res_prefix}/gtk-dark.css" 2>/dev/null | grep -c '#7233CD' || echo 0)
    echo "    verify $gres_ver: magenta=$magenta_count violet=$violet_count"
}

process_gresource "$AIOBI_ROOT/gtk-3.0"
process_gresource "$AIOBI_ROOT/gtk-4.0"

# Cleanup working dir (backups at *.magenta.bak preserved)
rm -rf /tmp/aiobi-gres-work

# ----- 6) Final verification -------------------------------------------------
echo
echo "== Verification =="
ls -la "$AIOBI_ROOT/" 2>/dev/null | grep -E "gtk-|index"
echo
echo "  Disk CSS magenta remnants: $(grep -rc '#B34CB3' "$AIOBI_ROOT/gtk-3.0" "$AIOBI_ROOT/gtk-4.0" 2>/dev/null | grep -v ':0$' | wc -l) files"
echo "  Backups: $(ls "$AIOBI_ROOT.day5.bak" 2>/dev/null && echo yes) + gresource *.magenta.bak"

echo "==> 03 done (V2 Day 5 full-clone + gresource pipeline)"
echo "    Effect: GTK 3+4 apps carry Aïobi violet accent + all Yaru widget completeness."
