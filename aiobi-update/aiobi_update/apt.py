# aiobi_update.apt — subprocess wrapper around apt-get / apt list.
#
# Contract
#   * Every apt-get invocation is non-interactive (-y where mutating,
#     DEBIAN_FRONTEND=noninteractive) and has a timeout so a stuck
#     transaction cannot hang the systemd unit indefinitely.
#   * Blacklisted packages are never named in an upgrade transaction —
#     aiobi-update targets specific package names via
#     `apt-get install --only-upgrade`, it never runs a blind
#     `apt-get dist-upgrade` that could pull a blacklisted package back
#     in as a side effect of dependency resolution.
#   * Lock contention (another apt/dpkg process holding the lock) is
#     detected from apt-get's stderr and raised as AptLockError so the
#     CLI can map it to exit code 3, distinct from a genuine package
#     failure (exit code 2).

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

REBOOT_REQUIRED_FLAG = Path("/var/run/reboot-required")

_LOCK_PATTERNS = re.compile(
    r"Could not get lock|Unable to lock the administration directory|"
    r"is another process using it",
    re.IGNORECASE,
)

_APT_ENV = dict(os.environ, DEBIAN_FRONTEND="noninteractive")

# apt list --upgradable output: "pkgname/suite version arch [upgradable from: ...]"
_UPGRADABLE_LINE = re.compile(r"^([^/]+)/")


class AptError(Exception):
    """A non-lock apt-get failure. Carries the command's stderr."""


class AptLockError(Exception):
    """apt-get could not acquire the dpkg/apt lock (another transaction
    in progress). Maps to CLI exit code 3."""


def _run(cmd: list[str], timeout: float = 600.0) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        env=_APT_ENV,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def apt_update() -> None:
    """`apt-get update -qq`. Raises AptLockError / AptError on failure."""
    result = _run(["apt-get", "update", "-qq"])
    if result.returncode != 0:
        if _LOCK_PATTERNS.search(result.stderr):
            raise AptLockError(result.stderr.strip())
        raise AptError(result.stderr.strip() or "apt-get update failed")


def list_upgradable(blacklist: frozenset[str] = frozenset()) -> list[str]:
    """Return upgradable package names, excluding anything in blacklist.
    Uses `apt list --upgradable`, which reads the already-updated
    package index populated by apt_update() and does not itself hit
    the network."""
    result = _run(["apt", "list", "--upgradable"], timeout=60.0)
    if result.returncode != 0:
        raise AptError(result.stderr.strip() or "apt list --upgradable failed")

    names: list[str] = []
    for line in result.stdout.splitlines():
        match = _UPGRADABLE_LINE.match(line)
        if not match:
            continue
        pkg = match.group(1)
        if pkg in blacklist:
            continue
        names.append(pkg)
    return names


def upgrade_packages(names: list[str]) -> tuple[list[str], list[str]]:
    """Upgrade each named package individually via
    `apt-get install --only-upgrade -y <pkg>` and return
    (succeeded, failed). Per-package invocation (rather than one
    combined transaction) is deliberate: it is the only way to surface
    a genuine partial-failure result (CLI exit code 2) instead of one
    failing package aborting the whole batch."""
    succeeded: list[str] = []
    failed: list[str] = []
    for pkg in names:
        result = _run(["apt-get", "install", "--only-upgrade", "-y", pkg])
        if result.returncode == 0:
            succeeded.append(pkg)
        else:
            if _LOCK_PATTERNS.search(result.stderr):
                raise AptLockError(result.stderr.strip())
            failed.append(pkg)
    return succeeded, failed


def upgrade_security_only() -> subprocess.CompletedProcess:
    """Restrict the transaction to the noble-security suite only, per
    the agreed spec for the overnight auto-apply path:
    `apt-get -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/ubuntu.sources
    -t noble-security -y upgrade`."""
    cmd = [
        "apt-get",
        "-o", "Dir::Etc::sourcelist=/etc/apt/sources.list.d/ubuntu.sources",
        "-t", "noble-security",
        "-y", "upgrade",
    ]
    result = _run(cmd)
    if result.returncode != 0 and _LOCK_PATTERNS.search(result.stderr):
        raise AptLockError(result.stderr.strip())
    return result


def reboot_required() -> bool:
    return REBOOT_REQUIRED_FLAG.exists()
