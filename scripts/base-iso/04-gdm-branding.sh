#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Base ISO — Step 04 — GDM greeter branding (full gresource swap)
# =============================================================================
# WHAT
#   Rebuilds the Yaru gnome-shell-theme.gresource with Aïobi assets +
#   gdm.css overrides and installs it via dpkg-divert on the canonical
#   Yaru path. Pipeline:
#     1. Full extraction of every resource under Yaru's gresource
#        (~151 entries on stock Noble) into a working tree.
#     2. Drop Aïobi PNGs (background + avatar) into the extracted tree.
#     3. Append the Aïobi override block to theme/gdm.css — brand colours
#        (iteration 1.2), Yaru inset box-shadow fix on the password entry
#        (iteration 1.4), fallback-symbolic StIcon kill (block 1.7),
#        Ubuntu logo container collapse (block 1.8).
#     4. Regenerate the XML manifest from `find` — every file on disk is
#        listed, no hand-maintained inventory.
#     5. Compile a structurally identical gresource + install at the
#        canonical Yaru path under a dpkg-divert Anti-Casse.
#
# WHY the full-extraction approach
#   Partial extraction (only gnome-shell.css) fails because Yaru's CSS
#   references dozens of internal SVG/PNG assets via resource://
#   URLs. Any asset missing from the recompiled binary causes gnome-shell
#   to fall back to Adwaita or blank the screen. Full extraction preserves
#   every reference exactly.
#
# WHY dpkg-divert on the Yaru path
#   On stock Noble the canonical /usr/share/gnome-shell/gnome-shell-theme.gresource
#   is an alternatives symlink pointing at
#   /usr/share/gnome-shell/theme/Yaru/gnome-shell-theme.gresource. Diverting
#   the Yaru file (rather than the alternatives symlink) survives both
#   yaru-theme-gnome-shell updates and any future re-registration of the
#   alternatives group by gnome-shell-common.
#
# WHY the four CSS blocks
#   - 1.2: brand colours on the background, entry, and clock/date.
#   - 1.4: Yaru renders the "border" of the password StEntry as an inset
#     box-shadow, not a border property — overriding box-shadow is what
#     actually swaps the orange to violet.
#   - 1.7: the white halo around the avatar was not a CSS border but a
#     StIcon child rendering avatar-default-symbolic (verified with a
#     `color: red` falsifiable test); zeroing its icon-size and colour
#     removes it without touching the parent .user-icon.
#   - 1.8: the Ubuntu logo at the bottom of the greeter is
#     .login-dialog-logo-bin — collapsing width/height/visibility hides
#     it. No Aïobi logo replacement in V1 (parked for a follow-up).
#
# ASSETS
#   Expected under /root/aiobi-base-assets/gdm/:
#     - aiobi_gdm_background.png
#     - aiobi_gdm_avatar.png
#   Override via AIOBI_GDM_ASSETS.
#
# SOURCES
#   - Cascade order + full extraction rationale: internal
#     GDM_Customization_Guide_US-1.4_PHASE1.md
#   - Yaru theme reference: https://github.com/ubuntu/yaru
#   - Halfline on GNOME Shell event flow (why we do not touch
#     #screenShield): https://blogs.gnome.org/halfline/2010/10/25/system-modal-dialogs/
#
# IDEMPOTENT: WORK dir is wiped on each run before extraction; dpkg-divert
#   --add is guarded by --list check.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

ASSETS_SRC="${AIOBI_GDM_ASSETS:-/root/aiobi-base-assets/gdm}"
WORK="/aiobi-gdm-build"
YARU_GRESOURCE="/usr/share/gnome-shell/theme/Yaru/gnome-shell-theme.gresource"
CANONICAL="/usr/share/gnome-shell/gnome-shell-theme.gresource"

echo "==> Aïobi — 04-gdm-branding.sh"

# ----- 1) Dependencies -------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get install -y libglib2.0-bin libxml2-utils

# ----- 2) Asset check --------------------------------------------------------
for f in aiobi_gdm_background.png aiobi_gdm_avatar.png; do
    if [ ! -f "$ASSETS_SRC/$f" ]; then
        echo "  ERROR: $ASSETS_SRC/$f missing — stage before running or set AIOBI_GDM_ASSETS."
        exit 1
    fi
done

# ----- 3) Fresh work tree + full extraction ---------------------------------
echo "  extracting Yaru gresource into $WORK/extracted"
rm -rf "$WORK"
mkdir -p "$WORK/extracted"

if [ ! -f "$YARU_GRESOURCE" ]; then
    echo "  ERROR: $YARU_GRESOURCE missing — is yaru-theme-gnome-shell installed?"
    exit 1
fi

for path in $(gresource list "$YARU_GRESOURCE"); do
    rel="${path#/org/gnome/shell/}"
    mkdir -p "$WORK/extracted/$(dirname "$rel")"
    gresource extract "$YARU_GRESOURCE" "$path" > "$WORK/extracted/$rel"
done

SRC_COUNT=$(gresource list "$YARU_GRESOURCE" | wc -l)
EXT_COUNT=$(find "$WORK/extracted" -type f | wc -l)
echo "  source entries : $SRC_COUNT"
echo "  extracted files: $EXT_COUNT"
[ "$SRC_COUNT" = "$EXT_COUNT" ] || { echo "  ERROR: extraction count mismatch — abort"; exit 1; }

# ----- 4) Drop Aïobi assets into the extracted tree -------------------------
cp "$ASSETS_SRC/aiobi_gdm_background.png" "$WORK/extracted/theme/aiobi_gdm_background.png"
cp "$ASSETS_SRC/aiobi_gdm_avatar.png"     "$WORK/extracted/theme/aiobi_gdm_avatar.png"

# ----- 5) Append the Aïobi override block to theme/gdm.css ------------------
# The block combines iteration 1.2 (brand colours), iteration 1.4 (Yaru
# box-shadow inset fix on the password entry), block 1.7 (StIcon overlay
# kill on the avatar), block 1.8 (Ubuntu logo container collapse).
GDM_CSS="$WORK/extracted/theme/gdm.css"
[ -f "$GDM_CSS" ] || { echo "  ERROR: $GDM_CSS missing in extracted tree"; exit 1; }

cat >> "$GDM_CSS" << 'EOF'

/* =================================================================== */
/* AIOBI OS — GDM LOGIN OVERRIDE                                       */
/* Brand: Black #0F1010 | White #F8F8F9 | Violet #4A3C5C | Lilas #E4D3E6 */
/* =================================================================== */

/* === ITERATION 1.2 — brand background + violet entry + white clock === */
#lockDialogGroup {
  background: #0F1010 url('resource:///org/gnome/shell/theme/aiobi_gdm_background.png') no-repeat center center !important;
  background-size: cover !important;
}

.login-dialog-clock,
.login-dialog-date,
.unlock-dialog-clock,
.unlock-dialog-date {
  color: #F8F8F9 !important;
}

.login-dialog .framed-user-icon,
.login-dialog .user-widget .user-icon,
.user-widget.horizontal .user-icon,
.user-widget.vertical .user-icon {
  background-image: url('resource:///org/gnome/shell/theme/aiobi_gdm_avatar.png') !important;
  background-size: cover !important;
  background-color: transparent !important;
  border: none !important;
}

.login-dialog .user-widget-label,
.login-dialog-username {
  color: #F8F8F9 !important;
}

/* === ITERATION 1.4 — Yaru fakes borders with inset box-shadow ======= */
.login-dialog .login-dialog-prompt-entry,
.login-dialog StEntry,
.login-dialog-prompt-entry {
  border: 1px solid #4A3C5C !important;
  border-radius: 4px !important;
  background-color: rgba(15, 16, 16, 0.25) !important;
  color: #F8F8F9 !important;
  caret-color: #E4D3E6 !important;
  selection-background-color: #4A3C5C !important;
  box-shadow: inset 0 0 0 1px #4A3C5C !important;
  padding: 6px 10px;
}

.login-dialog StEntry:focus,
.login-dialog .login-dialog-prompt-entry:focus {
  border: 1px solid #E4D3E6 !important;
  box-shadow: inset 0 0 0 1px #E4D3E6 !important;
}

/* === BLOCK 1.7 — kill the fallback-symbolic StIcon overlay =========== */
/* Root cause: userWidget.js renders avatar-default-symbolic as a StIcon
   child of .user-icon whenever AccountsService reports Icon=; Yaru's
   `.user-icon { color: #F7F7F7 }` recolours the symbolic SVG to near-
   white, producing the visible halo. Zero the icon size and paint it
   transparent so only our aiobi_gdm_avatar.png background remains. */
.login-dialog .framed-user-icon StIcon,
.login-dialog .user-widget .user-icon StIcon,
.user-widget.vertical .user-icon StIcon,
.user-widget.horizontal .user-icon StIcon {
  icon-size: 0 !important;
  color: transparent !important;
  background: none !important;
}

/* === BLOCK 1.8 — collapse the Ubuntu logo container ================== */
.login-dialog-logo-bin,
.gdm-logo-bin,
#lockDialogGroup .login-dialog-logo-bin,
.login-dialog-logo-bin StWidget,
.login-dialog-logo-bin StIcon {
  background-image: none !important;
  background: none !important;
  width: 0 !important;
  height: 0 !important;
  padding: 0 !important;
  margin: 0 !important;
  icon-size: 0 !important;
  color: transparent !important;
  visibility: hidden !important;
}
EOF
echo "  appended AIOBI OS override block to theme/gdm.css"

# ----- 6) Regenerate the XML manifest from the on-disk tree -----------------
echo "  regenerating XML manifest"
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<gresources>'
    echo '  <gresource prefix="/org/gnome/shell">'
    ( cd "$WORK/extracted" && find . -type f | sed 's|^\./||' | sort | \
        awk '{ print "    <file>" $0 "</file>" }' )
    echo '  </gresource>'
    echo '</gresources>'
} > "$WORK/gnome-shell-theme.gresource.xml"

xmllint --noout "$WORK/gnome-shell-theme.gresource.xml"
MANIFEST_COUNT=$(grep -c '<file>' "$WORK/gnome-shell-theme.gresource.xml")
echo "  manifest entries: $MANIFEST_COUNT"

# ----- 7) Compile -----------------------------------------------------------
echo "  compiling gresource"
glib-compile-resources \
    --sourcedir="$WORK/extracted" \
    --target="$WORK/gnome-shell-theme.gresource" \
    "$WORK/gnome-shell-theme.gresource.xml"

file "$WORK/gnome-shell-theme.gresource"
gresource list "$WORK/gnome-shell-theme.gresource" | grep aiobi_gdm

# ----- 8) Install via dpkg-divert on the canonical Yaru path ----------------
if ! dpkg-divert --list | grep -q " $YARU_GRESOURCE$"; then
    echo "  registering dpkg-divert on $YARU_GRESOURCE"
    dpkg-divert --local --rename --add "$YARU_GRESOURCE"
else
    echo "  dpkg-divert on $YARU_GRESOURCE already registered — skip"
fi

cp "$WORK/gnome-shell-theme.gresource" "$YARU_GRESOURCE"
chown root:root "$YARU_GRESOURCE"
chmod 644       "$YARU_GRESOURCE"

# The alternatives symlink at $CANONICAL keeps pointing at $YARU_GRESOURCE,
# so overwriting the Yaru file is what GDM actually loads at boot.

# ----- 9) Verification -------------------------------------------------------
echo
echo "  Verification:"
printf "    dpkg-divert entries    : "; dpkg-divert --list | grep -c gnome-shell-theme || true
printf "    canonical -> "; readlink -f "$CANONICAL"
printf "    aiobi PNGs in live file: "
gresource list "$YARU_GRESOURCE" | grep -c aiobi_gdm || true
printf "    AIOBI marker in gdm.css: "
gresource extract "$YARU_GRESOURCE" /org/gnome/shell/theme/gdm.css \
    | grep -c "AIOBI OS" || true

echo "==> 04 done"
