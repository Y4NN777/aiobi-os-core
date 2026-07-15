#!/usr/bin/env bash
# ============================================================================
# Aïobi OS — Step 21 — Configure terminal auto-completion
# ----------------------------------------------------------------------------
# Purpose : deliver a first-class TAB experience in every new Aïobi OS user
#           session — apt/dpkg subcommands, systemctl unit names, git
#           refs, argcomplete-enabled Python CLIs. Ships two layers:
#             1. the `bash-completion` package + `python3-argcomplete` for
#                dynamic completion of Python entry-points.
#             2. a readline configuration that upgrades the raw TAB into
#                a menu-cycling experience (menu-complete on TAB,
#                menu-complete-backward on Shift+TAB, show-all-if-ambiguous,
#                menu-complete-display-prefix), injected into both
#                /etc/skel/.bashrc (template for every future user) and
#                the currently invoking user's ~/.bashrc.
#
# References
#   - `man bash` (READLINE section — bind, menu-complete, show-all-if-ambiguous)
#   - /usr/share/doc/bash-completion/README (dynamic loader,
#     $BASH_COMPLETION_USER_DIR conventions)
#   - `argcomplete` docs — global registration via `activate-global-python-argcomplete`
#     is deliberately NOT used here; per-CLI activation lives in each tool.
#
# Idempotency
#   Every write is gated by an absence-check before it fires:
#     - packages: `dpkg -s` before `apt install`
#     - sourcing block: `grep -qF` on a distinctive marker line
#     - each readline bind: `grep -qF` on the literal bind line
#     - directories: `mkdir -p` (naturally idempotent)
#     - hook file: `touch` (naturally idempotent, does not overwrite)
#   Re-running the script on an already-configured system produces
#   "No change — everything is already in place." and exits 0.
#
# DRY_RUN
#   Export `DRY_RUN=true` to see every action the script WOULD take without
#   touching the filesystem. Default is DRY_RUN=false. Verification block
#   still runs at the end.
#
# Ownership
#   Files and directories created under the target user's HOME are
#   `chown`'d back to that user when the script runs under sudo — created
#   as root, owned by user. `/etc/skel/.bashrc` remains owned by root.
#
# Ordering
#   Standalone. Recommended late in the pipeline, right before
#   06-apply-persistence.sh so /etc/skel is fully populated at the moment
#   persistence copies skel into place. Safe to run at any point; nothing
#   in earlier steps depends on the bash-completion package being present.
# ============================================================================

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Must run as root (sudo)."; exit 1; }

# ---- Config ----------------------------------------------------------------

DRY_RUN="${DRY_RUN:-false}"

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [[ -z "$TARGET_HOME" ]] || [[ ! -d "$TARGET_HOME" ]]; then
    echo "ERROR: could not resolve HOME for user '$TARGET_USER' via getent."
    echo "       cannot proceed — target user must exist in /etc/passwd."
    exit 4
fi
TARGET_BASHRC="$TARGET_HOME/.bashrc"

CHANGES=()

# ---- Helpers ---------------------------------------------------------------

# Marker string used to detect whether the bash-completion sourcing block has
# already been injected into a .bashrc. Present in Ubuntu 24.04 stock skel,
# so on a stock system the block is already there and we simply skip.
BC_MARKER='bash-completion/bash_completion'

# The four readline binds we want present in every Aïobi shell. Order matters
# for the summary output; string equality matters for the grep -qF gate.
READLINE_BINDS=(
    "bind 'TAB:menu-complete'"
    "bind '\"\\e[Z\":menu-complete-backward'"
    "bind \"set show-all-if-ambiguous on\""
    "bind \"set menu-complete-display-prefix on\""
)

# The sourcing block to append when BC_MARKER is absent from a target file.
read -r -d '' BC_SOURCE_BLOCK <<'EOF' || true

# ── bash-completion ──────────────────────────────────────────────
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
EOF

# Header prepended to the readline binds section (only appended once, guarded
# by the presence of the first bind line via grep -qF).
BINDS_HEADER='# ── Aïobi readline: menu-complete on TAB / Shift-TAB ─────────────'

log_change() {
    CHANGES+=("$1")
}

do_or_dry() {
    # Runs the command unless DRY_RUN=true, in which case it is only echoed.
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY_RUN] would run: $*"
    else
        "$@"
    fi
}

append_to_file() {
    # append_to_file <file> <content>
    # In DRY_RUN mode, prints what would be appended. Otherwise, appends.
    local file="$1"
    local content="$2"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY_RUN] would append to $file:"
        printf '    | %s\n' $(printf '%s' "$content" | head -c 200)
    else
        printf '%s\n' "$content" >> "$file"
    fi
}

chown_to_target() {
    # chown a path back to $TARGET_USER when running under sudo (only if the
    # invoking user was NOT root originally — i.e. SUDO_USER is set). Idempotent.
    local path="$1"
    if [[ -n "${SUDO_USER:-}" ]] && [[ "$TARGET_USER" != "root" ]]; then
        do_or_dry chown "$TARGET_USER:$TARGET_USER" "$path"
    fi
}

inject_sourcing_block() {
    # inject_sourcing_block <target-file> <human-label>
    # Appends BC_SOURCE_BLOCK to the target file if BC_MARKER is absent.
    local file="$1"
    local label="$2"
    if [[ ! -f "$file" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY_RUN] would create $file (missing) and inject sourcing block"
        else
            touch "$file"
        fi
        log_change "created $file ($label)"
    fi
    if grep -qF "$BC_MARKER" "$file" 2>/dev/null; then
        echo "  sourcing block already present in $file — skipping"
        return 0
    fi
    append_to_file "$file" "$BC_SOURCE_BLOCK"
    log_change "injected bash-completion sourcing block into $file ($label)"
}

inject_readline_binds() {
    # inject_readline_binds <target-file> <human-label>
    # For each bind line, if grep -qF misses it, append it. A one-line
    # header comment is written the first time any bind is added.
    local file="$1"
    local label="$2"
    local bind
    local header_needed=false

    # Determine if any bind is missing — controls whether we emit the header.
    for bind in "${READLINE_BINDS[@]}"; do
        if ! grep -qF -- "$bind" "$file" 2>/dev/null; then
            header_needed=true
            break
        fi
    done

    if [[ "$header_needed" == "true" ]] && ! grep -qF -- "$BINDS_HEADER" "$file" 2>/dev/null; then
        append_to_file "$file" ""
        append_to_file "$file" "$BINDS_HEADER"
        log_change "added readline-binds header to $file ($label)"
    fi

    for bind in "${READLINE_BINDS[@]}"; do
        if grep -qF -- "$bind" "$file" 2>/dev/null; then
            echo "  bind already present in $file: $bind"
        else
            append_to_file "$file" "$bind"
            log_change "added to $file: $bind"
        fi
    done
}

# ---- 1. Package install ----------------------------------------------------

echo "== 1. Package install =="

APT_UPDATED=false

for pkg in bash-completion python3-argcomplete; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        echo "  $pkg — already present"
    else
        if [[ "$APT_UPDATED" == "false" ]]; then
            do_or_dry apt-get update -qq
            APT_UPDATED=true
        fi
        do_or_dry apt-get install -y "$pkg"
        log_change "installed package: $pkg"
    fi
done

# ---- 2. Inject into /etc/skel/.bashrc --------------------------------------

echo
echo "== 2. /etc/skel/.bashrc (template for every new user) =="

SKEL_BASHRC=/etc/skel/.bashrc
if [[ ! -f "$SKEL_BASHRC" ]]; then
    echo "  WARNING: $SKEL_BASHRC does not exist on this system — creating minimal skeleton."
    if [[ "$DRY_RUN" != "true" ]]; then
        touch "$SKEL_BASHRC"
        chmod 0644 "$SKEL_BASHRC"
    fi
    log_change "created $SKEL_BASHRC (was missing)"
fi
inject_sourcing_block "$SKEL_BASHRC" "system skel template"
inject_readline_binds "$SKEL_BASHRC" "system skel template"

# ---- 3. Inject into invoking user's ~/.bashrc ------------------------------

echo
echo "== 3. $TARGET_BASHRC (invoking user: $TARGET_USER) =="

if [[ ! -f "$TARGET_BASHRC" ]]; then
    echo "  $TARGET_BASHRC does not exist — creating."
    if [[ "$DRY_RUN" != "true" ]]; then
        touch "$TARGET_BASHRC"
        chmod 0644 "$TARGET_BASHRC"
    fi
    chown_to_target "$TARGET_BASHRC"
    log_change "created $TARGET_BASHRC"
fi
inject_sourcing_block "$TARGET_BASHRC" "user $TARGET_USER"
inject_readline_binds "$TARGET_BASHRC" "user $TARGET_USER"
chown_to_target "$TARGET_BASHRC"

# ---- 4. User completions directory -----------------------------------------

echo
echo "== 4. User completions directory (BASH_COMPLETION_USER_DIR) =="

USER_COMPLETIONS_DIR="$TARGET_HOME/.local/share/bash-completion/completions"
if [[ -d "$USER_COMPLETIONS_DIR" ]]; then
    echo "  $USER_COMPLETIONS_DIR — already present"
else
    do_or_dry mkdir -p "$USER_COMPLETIONS_DIR"
    log_change "created directory: $USER_COMPLETIONS_DIR"
fi
# Chown the whole .local tree elements we may have created.
chown_to_target "$TARGET_HOME/.local"
chown_to_target "$TARGET_HOME/.local/share"
chown_to_target "$TARGET_HOME/.local/share/bash-completion"
chown_to_target "$USER_COMPLETIONS_DIR"

# ---- 5. User hook file -----------------------------------------------------

echo
echo "== 5. User hook file ~/.config/bash_completion =="

USER_CFG_DIR="$TARGET_HOME/.config"
USER_HOOK_FILE="$USER_CFG_DIR/bash_completion"
if [[ ! -d "$USER_CFG_DIR" ]]; then
    do_or_dry mkdir -p "$USER_CFG_DIR"
    log_change "created directory: $USER_CFG_DIR"
fi
if [[ -f "$USER_HOOK_FILE" ]]; then
    echo "  $USER_HOOK_FILE — already present"
else
    do_or_dry touch "$USER_HOOK_FILE"
    log_change "created hook file: $USER_HOOK_FILE"
fi
chown_to_target "$USER_CFG_DIR"
chown_to_target "$USER_HOOK_FILE"

# ---- 6. Verification -------------------------------------------------------

echo
echo "== Verification =="

echo
echo "-- Package status --"
for pkg in bash-completion python3-argcomplete; do
    status="$(dpkg-query -W -f='${Status}\n' "$pkg" 2>/dev/null || echo 'not-installed')"
    printf "  %-24s %s\n" "$pkg" "$status"
done

echo
echo "-- /etc/skel/.bashrc sourcing block --"
if grep -qF "$BC_MARKER" "$SKEL_BASHRC" 2>/dev/null; then
    echo "  present"
else
    echo "  absent"
fi

echo
echo "-- $TARGET_BASHRC readline binds --"
for bind in "${READLINE_BINDS[@]}"; do
    if grep -qF -- "$bind" "$TARGET_BASHRC" 2>/dev/null; then
        printf "  present:  %s\n" "$bind"
    else
        printf "  ABSENT:   %s\n" "$bind"
    fi
done

echo
echo "-- User dirs / hook file --"
for path in "$USER_COMPLETIONS_DIR" "$USER_HOOK_FILE"; do
    if [[ -e "$path" ]]; then
        printf "  present:  %s\n" "$path"
    else
        printf "  ABSENT:   %s\n" "$path"
    fi
done

# ---- Final summary ---------------------------------------------------------

echo
echo "== Summary =="
if [[ "$DRY_RUN" == "true" ]]; then
    echo "  DRY_RUN mode — no changes were written."
fi
if [[ ${#CHANGES[@]} -eq 0 ]]; then
    echo "  No change — everything is already in place."
else
    echo "  ${#CHANGES[@]} modification(s):"
    for change in "${CHANGES[@]}"; do
        echo "    - $change"
    done
fi

echo
echo "== 21-configure-bash-completion.sh done =="
echo "Effect: TAB cycles through matches, Shift+TAB cycles backward, argcomplete-enabled"
echo "Python CLIs auto-complete, and every new Aïobi user inherits the same behaviour"
echo "via /etc/skel/.bashrc. Reload with: source ~/.bashrc  (or open a new terminal)."
