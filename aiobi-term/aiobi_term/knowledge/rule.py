"""Typed data structures for the aiobi-term knowledge base.

A `Rule` describes one deterministic diagnostic. It has:
  * an `id` — stable, kebab-case, category-prefixed (e.g. "net-tools/netstat")
  * a `category` from the `Category` enum
  * a `Match` — the trigger, on the command shape and/or the shell error text
  * a `cause_key` — i18n key resolved to a localized cause sentence
  * a `try_template` — the corrective one-liner, may reference variables
  * `confidence` — 1..10, used to break ties when multiple rules match
  * optional `since` — the Aïobi OS / Ubuntu version this rule became valid on
  * optional `references` — URLs (upstream docs, bug tracker) for auditability

`Match` may match on:
  * `command_regex` — the shape of the shell command the user ran
  * `error_regex` — the shell stderr / error output the user pasted via --error

If both are set, BOTH must match (AND semantics — used to encode a rule
that only fires when a specific command produces a specific error).
Rules matching on error text are more specific and win priority ties.

`LookupResult` is what the engine returns after a hit — the caller
prints `cause` on line 1 and `try_line` on line 2 to honour the
two-line explain contract.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Pattern


class Category(str, Enum):
    """Coarse classification of rules, used for ordering and reporting."""
    DEPRECATED_TOOL = "deprecated-tool"
    AIOBI_PURGED    = "aiobi-purged"
    SYSTEMD_ERROR   = "systemd-error"
    FS_ERROR        = "filesystem-error"
    NETWORK_ERROR   = "network-error"
    PACKAGE_MGR     = "package-manager"
    PYTHON_ERROR    = "python-error"
    GIT_ERROR       = "git-error"
    SSH_ERROR       = "ssh-error"
    DOCKER_ERROR    = "docker-error"
    DISPLAY_ERROR   = "display-error"


@dataclass(frozen=True)
class Match:
    """Trigger predicate. At least one of the two regexes must be set."""
    command_regex: Pattern[str] | None = None
    error_regex:   Pattern[str] | None = None

    def __post_init__(self) -> None:
        if self.command_regex is None and self.error_regex is None:
            raise ValueError(
                "Match requires at least one of command_regex or error_regex"
            )

    def matches(self, command: str, error: str) -> bool:
        """Return True if this rule fires on the given (command, error).

        If both regexes are set, BOTH must match (AND semantics).
        If only one is set, only that one must match.
        """
        if self.command_regex is not None:
            if not self.command_regex.search(command):
                return False
        if self.error_regex is not None:
            if not error or not self.error_regex.search(error):
                return False
        return True

    @property
    def specificity(self) -> int:
        """Return how specific this match is — used for priority ordering.

        A rule that matches both command AND error is more specific than
        one that matches only one of them, because it targets a precise
        (command, error) combination.
        """
        score = 0
        if self.command_regex is not None:
            score += 1
        if self.error_regex is not None:
            score += 2  # error match weighted higher — it's ground truth
        return score


@dataclass(frozen=True)
class Rule:
    """One deterministic diagnostic entry in the knowledge base."""
    id: str
    category: Category
    match: Match
    cause_key: str
    try_template: str
    confidence: int = 5
    since: str | None = None
    references: tuple[str, ...] = field(default_factory=tuple)

    def __post_init__(self) -> None:
        if not (1 <= self.confidence <= 10):
            raise ValueError(
                f"Rule {self.id!r} confidence must be 1..10, got {self.confidence}"
            )
        if not self.id or not self.cause_key or not self.try_template:
            raise ValueError(
                f"Rule {self.id!r} has an empty required field"
            )


@dataclass(frozen=True)
class LookupResult:
    """What the engine returns when a rule matched.

    The CLI prints `cause` verbatim on line 1 and `Try: {try_line}`
    on line 2 to match the two-line output contract shared with the
    LLM explain path.

    `rule_id` is exposed so an `--show-rule` audit flag can print
    which knowledge-base entry served the answer.
    """
    rule_id: str
    category: Category
    cause: str
    try_line: str
    confidence: int
