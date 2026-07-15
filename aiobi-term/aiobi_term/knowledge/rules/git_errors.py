"""Rules for common git operational errors."""

from __future__ import annotations

import re

from aiobi_term.knowledge.rule import Category, Match, Rule


_GIT_CMD = re.compile(r"^\s*git\b")


RULES: tuple[Rule, ...] = (
    Rule(
        id="git/not-a-repository",
        category=Category.GIT_ERROR,
        match=Match(
            command_regex=_GIT_CMD,
            error_regex=re.compile(r"not a git repository", re.IGNORECASE),
        ),
        cause_key="git.not_a_repository",
        try_template="git rev-parse --show-toplevel 2>/dev/null || git init",
        confidence=10,
    ),
    Rule(
        id="git/no-upstream",
        category=Category.GIT_ERROR,
        match=Match(
            command_regex=_GIT_CMD,
            error_regex=re.compile(
                r"no upstream branch|has no upstream branch|"
                r"the current branch .* has no upstream",
                re.IGNORECASE,
            ),
        ),
        cause_key="git.no_upstream",
        try_template="git push --set-upstream origin $(git branch --show-current)",
        confidence=10,
    ),
    Rule(
        id="git/push-rejected",
        category=Category.GIT_ERROR,
        match=Match(
            command_regex=_GIT_CMD,
            error_regex=re.compile(
                r"updates were rejected|non-fast-forward|"
                r"tip of your current branch is behind",
                re.IGNORECASE,
            ),
        ),
        cause_key="git.push_rejected",
        try_template="git pull --rebase && git push",
        confidence=9,
    ),
    Rule(
        id="git/detached-head",
        category=Category.GIT_ERROR,
        match=Match(
            command_regex=_GIT_CMD,
            error_regex=re.compile(r"you are in .detached HEAD.", re.IGNORECASE),
        ),
        cause_key="git.detached_head",
        try_template="git switch -c my-feature-branch",
        confidence=8,
    ),
)
