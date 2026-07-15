"""Rule matcher and priority resolver for the knowledge base.

Public entry point: `lookup(command, error, lang)`.

Algorithm:
  1. Enumerate every registered rule (via the loader, which imports
     all `aiobi_term.knowledge.rules.*` submodules and concatenates
     their `RULES` tuples).
  2. Filter to rules whose `Match` fires on the given (command, error).
  3. Rank the survivors by, in order:
        a) Match specificity (both regexes > command only > error only).
        b) Rule confidence (higher wins).
        c) Rule id lexicographic (deterministic tiebreak).
  4. Return the top-1 rule as a `LookupResult`, with the localized cause
     resolved via i18n and the try_template rendered with variables
     extracted from the command.

Try-template variables the engine substitutes:
    {cmd}      the full command string as passed by the user
    {cmd_bin}  the leading binary of the command (stripped of any
               leading `sudo`, quoting or absolute path)
    {arg1}     the first argument after the binary, if any (else '')
    {arg2}     the second argument after the binary, if any (else '')
    {argN}     the last non-flag argument (skipping tokens starting
               with `-`) — useful for `<tool> <verb> <target>` shapes
               such as `snap install firefox` or `apt install nginx`
               where the interesting token is `firefox` / `nginx`, not
               the verb.

Rendering is safe: if a template references an unknown variable,
`str.format_map` with a defaulting dict returns the placeholder text
unchanged rather than raising.
"""

from __future__ import annotations

import shlex

from aiobi_term.knowledge.i18n import Lang, translate
from aiobi_term.knowledge.loader import get_all_rules
from aiobi_term.knowledge.rule import LookupResult, Rule


class _TemplateVars(dict):
    """dict variant that returns '{key}' for missing keys instead of raising."""

    def __missing__(self, key: str) -> str:  # noqa: D401
        return "{" + key + "}"


def _extract_command_parts(command: str) -> dict[str, str]:
    """Return a rendering context with {cmd_bin, arg1, arg2, argN} from a
    command string.

    Handles a leading `sudo` (dropped) and absolute paths (basename
    kept for cmd_bin). Uses shlex to survive quoting; falls back to
    a naive split on shlex errors.

    argN is the last non-flag argument in the token stream — useful
    for patterns like `apt install nginx` or `snap remove firefox`
    where the interesting token is the last positional one, not the
    verb sub-command.
    """
    try:
        tokens = shlex.split(command)
    except ValueError:
        tokens = command.strip().split()
    if not tokens:
        return {"cmd_bin": "", "arg1": "", "arg2": "", "argN": ""}
    # Drop leading sudo + any of its flags
    if tokens[0] == "sudo":
        tokens = tokens[1:]
        while tokens and tokens[0].startswith("-"):
            tokens = tokens[1:]
    if not tokens:
        return {"cmd_bin": "", "arg1": "", "arg2": "", "argN": ""}
    cmd_bin = tokens[0].split("/")[-1]
    arg1 = tokens[1] if len(tokens) >= 2 else ""
    arg2 = tokens[2] if len(tokens) >= 3 else ""
    non_flag_tail = [t for t in tokens[1:] if not t.startswith("-")]
    argN = non_flag_tail[-1] if non_flag_tail else ""
    return {"cmd_bin": cmd_bin, "arg1": arg1, "arg2": arg2, "argN": argN}


def _render_try(template: str, command: str) -> str:
    """Substitute {cmd}, {cmd_bin}, {arg1}, {arg2}, {argN} in a try_template."""
    parts = _extract_command_parts(command)
    ctx = _TemplateVars(cmd=command, **parts)
    return template.format_map(ctx)


def _rank_key(rule: Rule) -> tuple[int, int, str]:
    """Priority key for a rule — higher tuple wins (sort reverse=True).

    Order:
      1. specificity — how many predicates match (weighted).
      2. confidence — 1..10 as declared on the rule.
      3. inverted id — kept lexicographic; used only as a stable tiebreak.
    """
    # id is inverted so lexicographic ascending id wins on tie (we sort desc)
    return (rule.match.specificity, rule.confidence, -sum(map(ord, rule.id)))


def lookup(command: str, error: str = "", lang: Lang | None = None) -> LookupResult | None:
    """Search the knowledge base for a rule matching (command, error).

    Returns the best-matching `LookupResult` or `None` if no rule fires.
    On `None`, the caller falls back to the LLM path.
    """
    hits: list[Rule] = [r for r in get_all_rules() if r.match.matches(command, error)]
    if not hits:
        return None
    hits.sort(key=_rank_key, reverse=True)
    winner = hits[0]
    cause = translate(winner.cause_key, lang)
    try_line = _render_try(winner.try_template, command)
    return LookupResult(
        rule_id=winner.id,
        category=winner.category,
        cause=cause,
        try_line=try_line,
        confidence=winner.confidence,
    )
