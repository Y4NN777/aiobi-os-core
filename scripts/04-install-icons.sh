#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Step 04 — Icon theme (Papirus recolor + Aïobi placeholders)
# =============================================================================
# WHAT
#   1. Install Papirus, Papirus-Dark, Papirus-Light via the official PPA.
#   2. Audit every fill colour in target categories — log to audit.log
#      BEFORE touching anything.
#   3. Surgical sed-recolor on:
#         places/        (folder + trash + bookmarks + network)
#         apps/          (4 system apps only — file mgr, settings, store, terminal)
#         status/        (wifi, battery, indicators)
#         devices/       (usb, disks, printers)
#         actions/       (copy, paste, search, edit)
#         emblems/       (badges)
#      Replace ONLY the known Papirus base hex values, never #ffffff /
#      "white" / "none" / opacity / stroke values.
#   4. Apply to BOTH Papirus/ AND Papirus-Dark/ (Papirus-Light too if present).
#   5. NEVER touch: Brave, OnlyOffice, mimetypes/ (preserves file-type colour
#      semantics — PDF red, video purple, etc).
#   6. Backup originals to /usr/share/icons/Papirus-Aiobi-backup/<variant>/.
#   7. Install the 5 Aïobi placeholder SVGs (./icons/) into a new theme
#      /usr/share/icons/Aiobi/ that inherits from Papirus (light) /
#      Papirus-Dark (dark) so the placeholders show next to recoloured
#      Papirus icons regardless of user's chosen colour scheme.
#   8. Set icon-theme = 'Aiobi' system-wide (live + persisted via script 06).
#
# WHY NOT papirus-folders -C "#7233CD"
#   Research confirmed (https://github.com/PapirusDevelopmentTeam/papirus-folders/blob/master/papirus-folders):
#     papirus-folders only accepts NAMED presets (violet, magenta, …), not
#     arbitrary hex. The closest preset "violet" maps to #7e57c2 — visibly
#     OFF brand from Aïobi #7233CD. We therefore bypass papirus-folders
#     and apply manual sed on the Papirus blue base (#5294e2 / #4877b1 /
#     #1d344f).
#
# PAPIRUS BASE PALETTE (from build_color_folders.sh)
#   Primary   #5294e2  ← surface (largest filled area)
#   Secondary #4877b1  ← border / darker face
#   Symbol    #1d344f  ← inner detail / shadow
#   Paper     #e4e4e4  ← preserved (off-white background paper)
#
# AÏOBI MAPPING
#   #5294e2 → #7233CD   (aio-violet, primary surface)
#   #4877b1 → #5C24A8   (aio-violet-700, darker face)
#   #1d344f → #2D1755   (deeper violet — symbol stays dark for contrast)
#   #e4e4e4 → unchanged (paper)
#
# SOURCES
#   - https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/blob/master/tools/build_color_folders.sh
#   - https://github.com/PapirusDevelopmentTeam/papirus-folders
#   - https://launchpad.net/~papirus/+archive/ubuntu/papirus
#
# IDEMPOTENT: backup is preserved on first run; subsequent runs restore from
#   backup before re-applying, so palette can be iterated safely.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

HERE="$(cd "$(dirname "$0")/.." && pwd)"
PLACEHOLDER_DIR="$HERE/icons"
BACKUP_ROOT="/usr/share/icons/Papirus-Aiobi-backup"
AUDIT_LOG="/var/log/aiobi-icon-audit.log"

AIOBI_THEME_DIR="/usr/share/icons/Aiobi"

# Papirus → Aïobi recolor map (primary | secondary | symbol)
P_PRIMARY="#5294e2";   A_PRIMARY="#7233CD"
P_SECONDARY="#4877b1"; A_SECONDARY="#5C24A8"
P_SYMBOL="#1d344f";    A_SYMBOL="#2D1755"

# Categories to recolor (strict — apps/ is SELECTIVE; mimetypes/ untouched)
CATEGORIES=(places status devices actions emblems)

# Selective apps — only these system app icons get the violet treatment
APP_TARGETS=(
    system-file-manager.svg
    org.gnome.Nautilus.svg
    preferences-system.svg
    org.gnome.Settings.svg
    system-software-install.svg
    org.gnome.Software.svg
    utilities-terminal.svg
    org.gnome.Terminal.svg
    org.gnome.Console.svg
)

# NEVER touch — third-party app branding
APP_NEVER=(
    brave-browser
    brave
    onlyoffice
    onlyoffice-desktopeditors
)

echo "==> Aïobi — 04-install-icons.sh"

# ----- 1) Install Papirus PPA + packages -------------------------------------
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq software-properties-common
if ! grep -rq "papirus/papirus" /etc/apt/sources.list.d/ 2>/dev/null; then
    add-apt-repository -y ppa:papirus/papirus
fi
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq papirus-icon-theme

# ----- 2) Locate installed variants ------------------------------------------
VARIANTS=()
for v in Papirus Papirus-Dark Papirus-Light; do
    if [ -d "/usr/share/icons/$v" ]; then
        VARIANTS+=("$v")
    fi
done
echo "  variants detected: ${VARIANTS[*]}"

# ----- 3) Audit-FIRST (per brief: never guess hex) ---------------------------
mkdir -p "$(dirname "$AUDIT_LOG")"
: > "$AUDIT_LOG"
echo "==> Audit pass — unique fills per category (no writes yet)"
{
    echo "# Aïobi icon audit — $(date -u +%FT%TZ)"
    for v in "${VARIANTS[@]}"; do
        for cat in "${CATEGORIES[@]}"; do
            d="/usr/share/icons/$v/64x64/$cat"
            [ -d "$d" ] || continue
            echo "--- $v / $cat ---"
            grep -rhoE 'fill:#[0-9a-fA-F]{6}' "$d" 2>/dev/null | sort | uniq -c | sort -rn | head -20
        done
    done
} >> "$AUDIT_LOG"
echo "  audit written to $AUDIT_LOG"

# ----- 4) Backup originals before any sed ------------------------------------
mkdir -p "$BACKUP_ROOT"
for v in "${VARIANTS[@]}"; do
    if [ ! -d "$BACKUP_ROOT/$v" ]; then
        echo "  backup → $BACKUP_ROOT/$v"
        cp -a "/usr/share/icons/$v" "$BACKUP_ROOT/$v"
    else
        # Restore from backup so we always recolor a clean tree (idempotent)
        echo "  restore → $BACKUP_ROOT/$v → /usr/share/icons/$v (idempotent run)"
        rsync -a --delete "$BACKUP_ROOT/$v/" "/usr/share/icons/$v/"
    fi
done

# ----- 5) Surgical sed-recolor -----------------------------------------------
#
# We use individual targeted replacements — never a blanket #XXXXXX→#7233CD.
# Order matters: replace the LONGEST/MOST-SPECIFIC patterns first so the
# secondary hex doesn't accidentally get re-substituted by a primary pass.

recolor_file() {
    local f="$1"
    # Skip files that are NEVER touched
    local base; base=$(basename "$f" .svg)
    for skip in "${APP_NEVER[@]}"; do
        [[ "$base" == "$skip"* ]] && return 0
    done
    # Per-file backup (cheap — SVG is text) before the in-place edit
    cp "$f" "$f.bak"
    # Surgical replacements — case-insensitive so #5294E2 = #5294e2 hits too
    sed -i \
        -e "s/$P_PRIMARY/$A_PRIMARY/Ig" \
        -e "s/$P_SECONDARY/$A_SECONDARY/Ig" \
        -e "s/$P_SYMBOL/$A_SYMBOL/Ig" \
        "$f"
    # Cleanup the .bak — backup tree above is the canonical safety net
    rm -f "$f.bak"
}

recolor_category() {
    local variant="$1" category="$2"
    local root="/usr/share/icons/$variant"
    [ -d "$root" ] || return 0
    # Loop every size folder (16x16 … 128x128 + scalable)
    while IFS= read -r -d '' f; do
        recolor_file "$f"
    done < <(find "$root" -path "*/$category/*.svg" -print0)
}

recolor_app_targets() {
    local variant="$1"
    local root="/usr/share/icons/$variant"
    [ -d "$root" ] || return 0
    for target in "${APP_TARGETS[@]}"; do
        while IFS= read -r -d '' f; do
            recolor_file "$f"
        done < <(find "$root" -name "$target" -print0)
    done
}

for v in "${VARIANTS[@]}"; do
    echo "  recolor $v …"
    for cat in "${CATEGORIES[@]}"; do
        recolor_category "$v" "$cat"
    done
    recolor_app_targets "$v"
done

# ----- 6) Install Aïobi placeholder theme ------------------------------------
echo "  install /usr/share/icons/Aiobi (placeholder theme)"
mkdir -p "$AIOBI_THEME_DIR/scalable/apps"
cp "$PLACEHOLDER_DIR"/aiobi-*.svg "$AIOBI_THEME_DIR/scalable/apps/"

# Generate PNG raster fallbacks at standard sizes (Freedesktop naming).
# Rastering via rsvg-convert if available, else inkscape, else skip (SVG-only
# is still valid for GNOME 46 — apps that ignore SVG fall back to the
# inherited Papirus icon, which is acceptable for placeholders).
if command -v rsvg-convert >/dev/null 2>&1; then
    for size in 16 22 24 32 48 64 128 256; do
        out="$AIOBI_THEME_DIR/${size}x${size}/apps"
        mkdir -p "$out"
        for svg in "$AIOBI_THEME_DIR/scalable/apps"/*.svg; do
            name=$(basename "$svg" .svg)
            rsvg-convert -w $size -h $size "$svg" -o "$out/$name.png" 2>/dev/null || true
        done
    done
fi

cat > "$AIOBI_THEME_DIR/index.theme" << 'EOF'
[Icon Theme]
Name=Aiobi
Comment=Aïobi OS placeholder icons — inherits Papirus (recoloured to #7233CD)
Inherits=Papirus,Papirus-Dark,hicolor
Example=aiobi-start-menu
Directories=scalable/apps,16x16/apps,22x22/apps,24x24/apps,32x32/apps,48x48/apps,64x64/apps,128x128/apps,256x256/apps

[scalable/apps]
Size=64
Type=Scalable
MinSize=8
MaxSize=512
Context=Applications

[16x16/apps]
Size=16
Type=Fixed
Context=Applications

[22x22/apps]
Size=22
Type=Fixed
Context=Applications

[24x24/apps]
Size=24
Type=Fixed
Context=Applications

[32x32/apps]
Size=32
Type=Fixed
Context=Applications

[48x48/apps]
Size=48
Type=Fixed
Context=Applications

[64x64/apps]
Size=64
Type=Fixed
Context=Applications

[128x128/apps]
Size=128
Type=Fixed
Context=Applications

[256x256/apps]
Size=256
Type=Fixed
Context=Applications
EOF

# Refresh icon caches so GNOME picks up the new theme without a logout
for v in "${VARIANTS[@]}" Aiobi; do
    gtk-update-icon-cache -f -t "/usr/share/icons/$v" 2>/dev/null || true
done

echo "==> 04 done — Aïobi icon theme installed, Papirus variants recoloured to #7233CD"
echo "    Audit log: $AUDIT_LOG"
echo "    Backup:    $BACKUP_ROOT/"
