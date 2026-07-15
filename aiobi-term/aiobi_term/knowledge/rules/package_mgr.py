"""Rules for apt / dpkg errors on Ubuntu 24.04."""

from __future__ import annotations

import re

from aiobi_term.knowledge.rule import Category, Match, Rule


_APT_CMD = re.compile(r"^\s*(sudo\s+)?(apt(-get)?|aptitude)\b")


RULES: tuple[Rule, ...] = (
    Rule(
        id="apt/unable-to-locate",
        category=Category.PACKAGE_MGR,
        match=Match(
            command_regex=_APT_CMD,
            error_regex=re.compile(r"unable to locate package", re.IGNORECASE),
        ),
        cause_key="apt.unable_to_locate",
        try_template="apt-cache search {argN}",
        confidence=10,
    ),
    Rule(
        id="apt/lock",
        category=Category.PACKAGE_MGR,
        match=Match(
            command_regex=_APT_CMD,
            error_regex=re.compile(
                r"could not get lock|dpkg was interrupted|resource temporarily unavailable",
                re.IGNORECASE,
            ),
        ),
        cause_key="apt.lock",
        try_template="lsof /var/lib/dpkg/lock-frontend 2>/dev/null || ps aux | grep -E 'apt|dpkg' | grep -v grep",
        confidence=10,
    ),
    Rule(
        id="apt/broken-packages",
        category=Category.PACKAGE_MGR,
        match=Match(
            command_regex=_APT_CMD,
            error_regex=re.compile(
                r"broken packages|held broken packages|unmet dependencies",
                re.IGNORECASE,
            ),
        ),
        cause_key="apt.broken_packages",
        try_template="sudo apt --fix-broken install",
        confidence=9,
    ),
    Rule(
        id="apt/gpg-error",
        category=Category.PACKAGE_MGR,
        match=Match(
            command_regex=_APT_CMD,
            error_regex=re.compile(
                r"NO_PUBKEY|GPG error|the following signatures were invalid",
                re.IGNORECASE,
            ),
        ),
        cause_key="apt.gpg_error",
        try_template="apt-key list 2>/dev/null; ls /etc/apt/trusted.gpg.d/",
        confidence=9,
    ),
    Rule(
        id="dpkg/status-error",
        category=Category.PACKAGE_MGR,
        match=Match(
            error_regex=re.compile(
                r"dpkg was interrupted|configure needs to be finished|"
                r"needs to be reinstalled",
                re.IGNORECASE,
            ),
        ),
        cause_key="dpkg.status_error",
        try_template="sudo dpkg --configure -a",
        confidence=10,
    ),
)
