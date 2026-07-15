#!/usr/bin/env bash
# =============================================================================
# Test — Step 21 — Bash intelligent TAB behaviour
# =============================================================================
# Verifies that:
#   - the bash-completion package is installed
#   - the system-wide loader script is present
#   - python3-argcomplete is NOT installed (it hijacks -D and breaks git/
#     apt/systemctl completion)
#   - /etc/bash_completion.d/global-python-argcomplete is NOT installed
#   - /etc/skel/.bashrc carries the Aïobi TAB-behaviour marker
#   - every existing /home/<user>/.bashrc carries the same marker
# Optionally, when this test is SOURCED under an interactive shell, checks
# that `complete -p -D` resolves to the bash-completion _completion_loader.
# When executed as a normal (non-interactive) script, the interactive check
# is skipped rather than reported as a failure.
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 21 — bash intelligent TAB behaviour installed"

# 1. Package present, argcomplete absent (documented -D hijack).
assert_pkg bash-completion
assert_no_pkg python3-argcomplete

# 2. System-wide loader must be present so completions load in every shell.
assert_file /etc/profile.d/bash_completion.sh

# 3. The argcomplete global-loader must NOT be dropped in — it is what
# breaks git/apt/systemctl TAB when python3-argcomplete is installed.
assert_no_file /etc/bash_completion.d/global-python-argcomplete

# 4. The Aïobi marker must be in the skel bashrc and every user bashrc.
MARKER="# A$(printf '\xc3\xaf')obi OS — intelligent TAB behavior"

if [ -f /etc/skel/.bashrc ]; then
    assert_grep /etc/skel/.bashrc "$MARKER"
else
    fail "Aïobi marker in /etc/skel/.bashrc" "/etc/skel/.bashrc missing"
fi

# Walk /home/*/.bashrc — silence non-matching globs to a clean skip.
homes_seen=0
homes_ok=0
for rc in /home/*/.bashrc; do
    [ -f "$rc" ] || continue
    homes_seen=$((homes_seen + 1))
    if grep -qF -- "$MARKER" "$rc" 2>/dev/null; then
        homes_ok=$((homes_ok + 1))
        pass "Aïobi marker in $rc"
    else
        fail "Aïobi marker in $rc" "not injected"
    fi
done
if [ "$homes_seen" -eq 0 ]; then
    skip "Aïobi marker in /home/*/.bashrc" "no user home found (chroot build stage)"
fi

# 5. Interactive-only readline probe. Only meaningful in an interactive
# shell where bash-completion has run its post-source setup — inside the
# non-interactive test process it always looks empty. Skip cleanly so the
# harness stays green.
if [[ $- == *i* ]]; then
    if complete -p -D 2>/dev/null | grep -q "_completion_loader"; then
        pass "readline -D handler is _completion_loader"
    else
        fail "readline -D handler is _completion_loader" \
             "handler is $(complete -p -D 2>/dev/null || echo unset)"
    fi
else
    skip "readline -D handler is _completion_loader" \
         "non-interactive context; only meaningful when the test is sourced from a login shell"
fi

finalize
