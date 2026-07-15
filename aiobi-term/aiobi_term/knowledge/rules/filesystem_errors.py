"""Rules for the most common filesystem-layer errors on Linux.

Purely error-driven — no command shape restriction (these can arise
from any command that touches the filesystem).
"""

from __future__ import annotations

import re

from aiobi_term.knowledge.rule import Category, Match, Rule


RULES: tuple[Rule, ...] = (
    Rule(
        id="fs/permission-denied",
        category=Category.FS_ERROR,
        match=Match(error_regex=re.compile(r"permission denied", re.IGNORECASE)),
        cause_key="fs.permission_denied",
        try_template="sudo {cmd}",
        confidence=8,
    ),
    Rule(
        id="fs/no-such-file",
        category=Category.FS_ERROR,
        match=Match(error_regex=re.compile(r"no such file or directory", re.IGNORECASE)),
        cause_key="fs.no_such_file",
        try_template="ls -la $(dirname {arg1})",
        confidence=8,
    ),
    Rule(
        id="fs/disk-full",
        category=Category.FS_ERROR,
        match=Match(error_regex=re.compile(r"no space left on device", re.IGNORECASE)),
        cause_key="fs.disk_full",
        try_template="df -h && du -sh /* 2>/dev/null | sort -h | tail -20",
        confidence=10,
    ),
    Rule(
        id="fs/read-only",
        category=Category.FS_ERROR,
        match=Match(error_regex=re.compile(r"read-only file system", re.IGNORECASE)),
        cause_key="fs.read_only",
        try_template="mount | grep 'on / '",
        confidence=10,
    ),
    Rule(
        id="fs/file-exists",
        category=Category.FS_ERROR,
        match=Match(error_regex=re.compile(r"file exists", re.IGNORECASE)),
        cause_key="fs.file_exists",
        try_template="ls -la {arg1}",
        confidence=7,
    ),
    Rule(
        id="fs/is-a-directory",
        category=Category.FS_ERROR,
        match=Match(error_regex=re.compile(r"is a directory", re.IGNORECASE)),
        cause_key="fs.is_directory",
        try_template="ls -la {arg1}",
        confidence=7,
    ),
)
