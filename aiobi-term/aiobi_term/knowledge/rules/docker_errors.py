"""Rules for common Docker client errors."""

from __future__ import annotations

import re

from aiobi_term.knowledge.rule import Category, Match, Rule


_DOCKER_CMD = re.compile(r"^\s*(sudo\s+)?docker\b")


RULES: tuple[Rule, ...] = (
    Rule(
        id="docker/daemon-not-running",
        category=Category.DOCKER_ERROR,
        match=Match(
            command_regex=_DOCKER_CMD,
            error_regex=re.compile(
                r"cannot connect to the docker daemon|is the docker daemon running",
                re.IGNORECASE,
            ),
        ),
        cause_key="docker.daemon_not_running",
        try_template="systemctl status docker 2>/dev/null || echo 'docker.io not installed'",
        confidence=10,
    ),
    Rule(
        id="docker/socket-permission",
        category=Category.DOCKER_ERROR,
        match=Match(
            command_regex=_DOCKER_CMD,
            error_regex=re.compile(
                r"permission denied while trying to connect to the docker daemon|"
                r"got permission denied.*docker\.sock",
                re.IGNORECASE,
            ),
        ),
        cause_key="docker.socket_permission",
        try_template="sudo usermod -aG docker $USER   # then re-login",
        confidence=10,
    ),
)
