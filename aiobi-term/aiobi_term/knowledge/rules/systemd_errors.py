"""Rules for common systemd operational errors.

These are error-driven — they fire only when the shell error text
supplied via --error matches. Command match is broad (any systemctl
invocation) but the error regex narrows to a specific class.
"""

from __future__ import annotations

import re

from aiobi_term.knowledge.rule import Category, Match, Rule


_SYSTEMCTL_CMD = re.compile(r"\bsystemctl\b")


RULES: tuple[Rule, ...] = (
    Rule(
        id="systemd/unit-not-found",
        category=Category.SYSTEMD_ERROR,
        match=Match(
            command_regex=_SYSTEMCTL_CMD,
            error_regex=re.compile(r"unit .* not found", re.IGNORECASE),
        ),
        cause_key="systemd.unit_not_found",
        try_template="systemctl list-unit-files --type=service | grep -i {arg1}",
        confidence=9,
    ),
    Rule(
        id="systemd/dependency-failed",
        category=Category.SYSTEMD_ERROR,
        match=Match(
            command_regex=_SYSTEMCTL_CMD,
            error_regex=re.compile(r"dependency (has )?failed|failed with result 'dependency'", re.IGNORECASE),
        ),
        cause_key="systemd.dependency_failed",
        try_template="systemctl list-dependencies {arg1} --failed",
        confidence=9,
    ),
    Rule(
        id="systemd/service-failed",
        category=Category.SYSTEMD_ERROR,
        match=Match(
            command_regex=_SYSTEMCTL_CMD,
            error_regex=re.compile(r"failed with result", re.IGNORECASE),
        ),
        cause_key="systemd.service_failed",
        try_template="journalctl -u {arg1} -e --no-pager | tail -40",
        confidence=8,
    ),
    Rule(
        id="systemd/load-error",
        category=Category.SYSTEMD_ERROR,
        match=Match(
            command_regex=_SYSTEMCTL_CMD,
            error_regex=re.compile(r"bad-setting|invalid|loaded: error", re.IGNORECASE),
        ),
        cause_key="systemd.load_error",
        try_template="systemd-analyze verify {arg1}",
        confidence=8,
    ),
)
