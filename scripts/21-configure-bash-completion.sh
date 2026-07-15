#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 21 — Terminal auto-completion (intelligent TAB behavior)
# ----------------------------------------------------------------------------
# Purpose : ensure the bash-completion framework is installed and active,
#           then inject a small set of readline bindings that give an
#           IDE-like TAB behavior (immediate listing of candidates,
#           cycle-through on subsequent TABs, case-insensitive matching,
#           coloured stat markers). Applied to `/etc/skel/.bashrc` so every
#           freshly-created user account inherits the behavior, and to the
#           invoking user's own `~/.bashrc` for immediate effect.
#
# What this script does NOT do
#   * Install `python3-argcomplete`. On Ubuntu 24.04 that package drops
#     `/etc/bash_completion.d/global-python-argcomplete`, which registers
#     itself as the default (`-D`) completion handler and OVERRIDES
#     bash-completion's dynamic loader — breaking TAB completion for git,
#     apt, systemctl and other everyday commands. It only benefits Python
#     CLIs that were built with `argcomplete`; developers who need it can
#     install it explicitly in their virtualenv. Excluded on purpose.
#   * Inject the `. /usr/share/bash-completion/bash_completion` sourcing
#     block into `.bashrc`. The `bash-completion` package already ships
#     `/etc/profile.d/bash_completion.sh` which sources the framework for
#     every interactive login shell system-wide. Duplicating it in
#     `.bashrc` adds no value and risks conflicts.
#   * Create `~/.local/share/bash-completion/completions/` or
#     `~/.config/bash_completion`. Neither is required for the baseline
#     UX; users who drop custom completions there can create the dirs
#     themselves.
#
# Idempotent : every injection is gated by a `grep -qF` on an Aïobi-
# specific marker string that Ubuntu's default `.bashrc` does not
# contain, so re-running the script never duplicates lines.
#
# DRY_RUN toggle : `DRY_RUN=true bash 21-configure-bash-completion.sh`
# prints what would change without writing.
#
# Ordering : run late in the pipeline, right before `06-apply-persistence.sh`
# so `/etc/skel` is fully populated before persistence seals it.
# ============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

DRY_RUN="${DRY_RUN:-false}"

# Resolve the target user (invoker under sudo, else current user, else root).
TARGET_USER="${SUDO_USER:-${USER:-root}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)
[ -n "$TARGET_HOME" ] || TARGET_HOME="/root"

echo "==> Aïobi — 21-configure-bash-completion.sh (target user: $TARGET_USER, DRY_RUN=$DRY_RUN)"

CHANGES=()

# ---- helpers ---------------------------------------------------------------
run() {
    # Execute the command unless DRY_RUN is on. Logs a dry-run marker.
    if [ "$DRY_RUN" = "true" ]; then
        echo "  [DRY_RUN] would run: $*"
        return 0
    fi
    "$@"
}

append_line() {
    # append_line <file> <line-content> — appends if not already present
    # (fixed-string match, no regex surprises).
    local file="$1" line="$2"
    [ -f "$file" ] || run touch "$file"
    if grep -qF -- "$line" "$file"; then
        return 0
    fi
    if [ "$DRY_RUN" = "true" ]; then
        echo "  [DRY_RUN] would append to $file: $line"
    else
        printf '%s\n' "$line" >> "$file"
    fi
    CHANGES+=("added to $file: $line")
}

chown_if_sudo() {
    # When running under sudo, ensure files written under the user home
    # are owned by that user, not root.
    local path="$1"
    if [ -n "${SUDO_USER:-}" ] && [ "$TARGET_USER" != "root" ] && [ -e "$path" ]; then
        run chown "$TARGET_USER:$TARGET_USER" "$path"
    fi
}

# ---- 1) Install bash-completion --------------------------------------------
echo
echo "== 1. Package install =="
if dpkg -s bash-completion >/dev/null 2>&1; then
    echo "  bash-completion — already installed"
else
    echo "  bash-completion — installing"
    run apt-get update -qq || true
    run apt-get install -y bash-completion
    CHANGES+=("installed package: bash-completion")
fi

# ---- 2) Verify /etc/profile.d/bash_completion.sh is present ---------------
echo
echo "== 2. System-wide loader (/etc/profile.d/bash_completion.sh) =="
if [ -f /etc/profile.d/bash_completion.sh ]; then
    echo "  /etc/profile.d/bash_completion.sh — present (loads framework for every interactive shell)"
else
    echo "  ⚠ /etc/profile.d/bash_completion.sh — MISSING (bash-completion install may be incomplete)"
    echo "  → try: sudo apt-get install --reinstall bash-completion"
fi

# ---- 3) Inject Aïobi readline binds ---------------------------------------
# One marker line + six bind lines. The marker is Aïobi-specific so the
# gate never false-positives on Ubuntu's default `.bashrc` content.
AIOBI_MARKER='# Aïobi OS — intelligent TAB behavior (menu-complete, case-insensitive, coloured)'
AIOBI_BINDS=(
    "bind 'TAB:menu-complete'"
    "bind '\"\\e[Z\":menu-complete-backward'"
    'bind "set show-all-if-ambiguous on"'
    'bind "set menu-complete-display-prefix on"'
    'bind "set completion-ignore-case on"'
    'bind "set colored-stats on"'
)

inject_binds_into() {
    local file="$1" label="$2"
    if [ ! -f "$file" ]; then
        echo "  $label ($file) — target file does not exist, skipping"
        return 0
    fi
    if grep -qF "$AIOBI_MARKER" "$file"; then
        echo "  $label — Aïobi bind block already present, skipping"
        return 0
    fi
    echo "  $label — injecting Aïobi bind block"
    append_line "$file" ""
    append_line "$file" "$AIOBI_MARKER"
    for b in "${AIOBI_BINDS[@]}"; do
        append_line "$file" "$b"
    done
}

echo
echo "== 3. /etc/skel/.bashrc (template for every new user) =="
inject_binds_into /etc/skel/.bashrc "skel"

echo
echo "== 4. $TARGET_HOME/.bashrc (current invoking user: $TARGET_USER) =="
inject_binds_into "$TARGET_HOME/.bashrc" "user"
chown_if_sudo "$TARGET_HOME/.bashrc"

# ---- 5) Verification -------------------------------------------------------
echo
echo "== Verification =="
echo
echo "-- Package status --"
printf '  %-24s %s\n' "bash-completion" "$(dpkg-query -W -f='${Status}\n' bash-completion 2>/dev/null || echo 'not installed')"
echo
echo "-- /etc/profile.d/bash_completion.sh --"
[ -f /etc/profile.d/bash_completion.sh ] && echo "  present" || echo "  MISSING"
echo
echo "-- Aïobi bind block in /etc/skel/.bashrc --"
grep -qF "$AIOBI_MARKER" /etc/skel/.bashrc 2>/dev/null && echo "  present" || echo "  absent"
echo
echo "-- Aïobi bind block in $TARGET_HOME/.bashrc --"
grep -qF "$AIOBI_MARKER" "$TARGET_HOME/.bashrc" 2>/dev/null && echo "  present" || echo "  absent"

# ---- 6) Summary ------------------------------------------------------------
echo
echo "== Summary =="
if [ "${#CHANGES[@]}" -eq 0 ]; then
    echo "  No change — everything is already in place."
else
    echo "  ${#CHANGES[@]} modification(s):"
    for c in "${CHANGES[@]}"; do
        echo "    - $c"
    done
fi

echo
echo "== 21-configure-bash-completion.sh done =="
echo "Effect: TAB immediately lists candidates and cycles through them on"
echo "each subsequent press. Shift+TAB cycles backward. Case is ignored."
echo "Type markers are coloured (dir blue, exec green, symlink cyan)."
echo "Reload with:  source ~/.bashrc  (or open a new terminal)."
