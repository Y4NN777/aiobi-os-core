"""Rules for common SSH client errors."""

from __future__ import annotations

import re

from aiobi_term.knowledge.rule import Category, Match, Rule


_SSH_CMD = re.compile(r"^\s*(ssh|scp|sftp|rsync)\b")


RULES: tuple[Rule, ...] = (
    Rule(
        id="ssh/permission-denied-publickey",
        category=Category.SSH_ERROR,
        match=Match(
            command_regex=_SSH_CMD,
            error_regex=re.compile(r"permission denied \(publickey\)", re.IGNORECASE),
        ),
        cause_key="ssh.permission_denied_publickey",
        try_template="ssh -vT {arg1} 2>&1 | grep -E 'identity file|Offering'",
        confidence=10,
    ),
    Rule(
        id="ssh/host-key-changed",
        category=Category.SSH_ERROR,
        match=Match(
            command_regex=_SSH_CMD,
            error_regex=re.compile(
                r"remote host identification has changed|"
                r"host key verification failed",
                re.IGNORECASE,
            ),
        ),
        cause_key="ssh.host_key_changed",
        try_template="ssh-keygen -R {arg1}",
        confidence=10,
    ),
    Rule(
        id="ssh/connection-refused",
        category=Category.SSH_ERROR,
        match=Match(
            command_regex=_SSH_CMD,
            error_regex=re.compile(r"connection refused", re.IGNORECASE),
        ),
        cause_key="ssh.connection_refused",
        try_template="nc -zv {arg1} 22",
        confidence=9,
    ),
)
