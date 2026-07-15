"""Rules for bash builtin commands mistaken for failures.

Empirical observation: when the user passes a bash builtin to
`aiobi-term --explain` without any error text, the LLM fallback path
tends to invent a spurious failure ("source is not recognized on Aïobi
OS…") because it defaults to "explain why the input failed" rather
than "recognise that no failure occurred". This module catches the
common builtins (source, cd, pwd, export, alias, unalias, history,
unset, read, shift, declare, type, echo) with a command-only match and
returns a "no failure to explain — this is a shell builtin" response
that short-circuits the LLM path.

Confidence deliberately low (5) so that any error-driven rule (which
has higher specificity because it matches on both `command_regex` AND
`error_regex`) wins on tie. If the user passes `--error "..."` on a
builtin that DID produce an error, the specific error rule fires
instead of this generic one.
"""

from __future__ import annotations

import re

from aiobi_term.knowledge.rule import Category, Match, Rule


_BUILTIN_CMD = re.compile(
    r"^\s*(source|\.|cd|pwd|export|alias|unalias|history|unset|"
    r"read|shift|declare|typeset|type|echo|printf|set|shopt|umask|"
    r"jobs|fg|bg|kill|wait|trap|exec|eval|exit|return|true|false)\b"
)


RULES: tuple[Rule, ...] = (
    Rule(
        id="shell-builtin/generic",
        category=Category.SHELL_BUILTIN,
        match=Match(command_regex=_BUILTIN_CMD),
        cause_key="builtin.no_failure",
        try_template="help {cmd_bin}   # bash builtin — check its documentation",
        confidence=5,
    ),
)
