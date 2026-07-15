"""Rules for common Python / pip errors on Ubuntu 24.04 (PEP 668)."""

from __future__ import annotations

import re

from aiobi_term.knowledge.rule import Category, Match, Rule


RULES: tuple[Rule, ...] = (
    Rule(
        id="python/module-not-found",
        category=Category.PYTHON_ERROR,
        match=Match(error_regex=re.compile(r"ModuleNotFoundError|No module named", re.IGNORECASE)),
        cause_key="python.module_not_found",
        try_template="apt-cache search python3-<name>   # or: python3 -m venv .venv && .venv/bin/pip install <name>",
        confidence=9,
    ),
    Rule(
        id="python/pep668",
        category=Category.PYTHON_ERROR,
        match=Match(error_regex=re.compile(
            r"externally-managed-environment|error: externally-managed",
            re.IGNORECASE,
        )),
        cause_key="python.pep668",
        try_template="python3 -m venv .venv && .venv/bin/pip install <package>",
        confidence=10,
    ),
    Rule(
        id="python/no-pip",
        category=Category.PYTHON_ERROR,
        match=Match(
            command_regex=re.compile(r"^\s*(sudo\s+)?pip3?\b"),
            error_regex=re.compile(r"command not found", re.IGNORECASE),
        ),
        cause_key="python.no_pip",
        try_template="sudo apt install python3-pip",
        confidence=10,
    ),
)
