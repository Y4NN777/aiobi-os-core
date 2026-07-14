# aiobi-term — shell integration for the Aïobi terminal AI assistant.
# Loaded by /etc/profile.d/ for every interactive login shell.

# --- Readline keybind ------------------------------------------------------
# Ctrl-X Ctrl-A sends the current input line through aiobi-term --cmd and
# prints the suggested shell command below the prompt. The user then
# presses Enter to run it, edits it, or hits Ctrl-C to discard.
#
# The suggestion is NEVER executed automatically. Human confirmation is
# required for every command that reaches the shell.

if [ -n "${BASH_VERSION:-}" ]; then
    bind -x '"\C-x\C-a": aiobi-term --cmd "$READLINE_LINE"' 2>/dev/null || true
fi

if [ -n "${ZSH_VERSION:-}" ]; then
    _aiobi_term_cmd() {
        aiobi-term --cmd "$BUFFER"
        zle reset-prompt
    }
    zle -N _aiobi_term_cmd
    bindkey '^X^A' _aiobi_term_cmd 2>/dev/null || true
fi
