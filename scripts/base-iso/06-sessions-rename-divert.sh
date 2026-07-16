#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Base ISO — Step 06 — Rename Ubuntu session labels
# =============================================================================
# WHAT
#   Rewrites the four vendor `.desktop` session files under
#   /usr/share/{xsessions,wayland-sessions}/ so the GDM gear-menu session
#   selector lists `Aïobi OS` / `Aïobi OS (Xorg)` / `Aïobi OS (Wayland)`
#   instead of the upstream Ubuntu labels. Each file is pinned via
#   dpkg-divert so gnome-session / ubuntu-session updates cannot revert
#   the labels.
#
# WHY reconstruct ï from raw bytes
#   Earlier attempts using literal `ï` in the script source or in a
#   heredoc produced `Name=A\Uffffffffi OS` on disk — a shell / heredoc
#   encoding round-trip corrupted the character. Building the string
#   from the UTF-8 bytes 0xc3 0xaf via `printf '\xc3\xaf'` inside the
#   script keeps the bytes constant regardless of the calling
#   environment's LANG / LC_ALL. The final `xxd` probe confirms the
#   round-trip on disk.
#
# WHY four files
#   Stock Noble ships exactly four session desktop files:
#     /usr/share/xsessions/ubuntu.desktop
#     /usr/share/xsessions/ubuntu-xorg.desktop
#     /usr/share/wayland-sessions/ubuntu.desktop
#     /usr/share/wayland-sessions/ubuntu-wayland.desktop
#   Any subset would leave a mixed selector, so we handle all four.
#
# SOURCES
#   - https://specifications.freedesktop.org/desktop-entry-spec/latest/
#   - https://manpages.ubuntu.com/manpages/noble/en/man1/dpkg-divert.1.html
#
# IDEMPOTENT: dpkg-divert --add guarded by --list; sed operates on the
#   .distrib copy each time, so re-running always produces the same
#   canonical output.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

echo "==> Aïobi — 06-sessions-rename-divert.sh"

# ----- 1) Reconstruct brand strings from raw UTF-8 bytes --------------------
I_TREMA=$(printf '\xc3\xaf')          # = ï, locale-independent
PLAIN_NAME="A${I_TREMA}obi OS"
XORG_NAME="A${I_TREMA}obi OS (Xorg)"
WAYLAND_NAME="A${I_TREMA}obi OS (Wayland)"
COMMENT="A${I_TREMA}obi OS desktop session"

SESSION_FILES=(
    /usr/share/xsessions/ubuntu.desktop
    /usr/share/xsessions/ubuntu-xorg.desktop
    /usr/share/wayland-sessions/ubuntu.desktop
    /usr/share/wayland-sessions/ubuntu-wayland.desktop
)

# ----- 2) Divert + rewrite each file ----------------------------------------
for f in "${SESSION_FILES[@]}"; do
    if [ ! -f "$f" ] && [ ! -f "$f.distrib" ]; then
        echo "  WARN: $f absent — skipping"
        continue
    fi

    if ! dpkg-divert --list | grep -q " $f$"; then
        echo "  registering dpkg-divert on $f"
        dpkg-divert --local --rename --add "$f"
    else
        echo "  dpkg-divert on $f already registered — skip"
    fi

    # Rewrite the Name= and Comment= lines by sedding the preserved .distrib
    # copy into the canonical path.
    sed -E \
        -e "s|^Name=Ubuntu on Xorg\$|Name=${XORG_NAME}|" \
        -e "s|^Name=Ubuntu on Wayland\$|Name=${WAYLAND_NAME}|" \
        -e "s|^Name=Ubuntu\$|Name=${PLAIN_NAME}|" \
        -e "s|^Comment=.*|Comment=${COMMENT}|" \
        "$f.distrib" > "$f"
    chmod 644 "$f"
    echo "  rewrote $(basename "$f")"
done

# ----- 3) Verification — the bytes 0xc3 0xaf must be present ----------------
echo
echo "  Verification (UTF-8 ï = c3 af must appear in every Name= line):"
for f in "${SESSION_FILES[@]}"; do
    [ -f "$f" ] || continue
    if grep -E '^Name=' "$f" | xxd | grep -q 'c3af'; then
        echo "    OK  $(basename "$f")"
    else
        echo "    FAIL $(basename "$f") — ï byte sequence missing"
    fi
done

echo "==> 06 done"
