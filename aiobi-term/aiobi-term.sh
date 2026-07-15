# aiobi-term — shell integration for the Aïobi terminal AI assistant.
# Loaded by /etc/profile.d/ for every interactive login shell.

# --- Readline keybinds -----------------------------------------------------
# Ctrl-X Ctrl-A sends the current input line through aiobi-term --cmd and
# prints the suggested shell command below the prompt. The user then
# presses Enter to run it, edits it, or hits Ctrl-C to discard.
# The suggestion is NEVER executed automatically. Human confirmation is
# required for every command that reaches the shell.
#
# Ctrl-X Ctrl-H invokes aiobi-term --explain on the LAST command from
# history. Use it right after a failed command to get a one-sentence
# explanation of the likely failure cause and a corrected alternative.
# The last command is NOT re-run — the model reasons from the command
# shape alone, so there is no risk of triggering side effects again.

_aiobi_explain_last() {
    local last_cmd
    last_cmd=$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//' | head -1)
    if [ -z "$last_cmd" ]; then
        echo "aiobi-term: no previous command in shell history to explain" >&2
        return 1
    fi
    aiobi-term --explain "$last_cmd"
}

if [ -n "${BASH_VERSION:-}" ]; then
    bind -x '"\C-x\C-a": aiobi-term --cmd "$READLINE_LINE"' 2>/dev/null || true
    bind -x '"\C-x\C-h": _aiobi_explain_last' 2>/dev/null || true
fi

if [ -n "${ZSH_VERSION:-}" ]; then
    _aiobi_term_cmd() {
        aiobi-term --cmd "$BUFFER"
        zle reset-prompt
    }
    _aiobi_term_explain() {
        _aiobi_explain_last
        zle reset-prompt
    }
    zle -N _aiobi_term_cmd
    zle -N _aiobi_term_explain
    bindkey '^X^A' _aiobi_term_cmd 2>/dev/null || true
    bindkey '^X^H' _aiobi_term_explain 2>/dev/null || true
fi
