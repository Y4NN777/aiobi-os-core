# aiobi_update.policy — /etc/aiobi/update.conf loader + blacklist.
#
# Format: INI, parsed with the stdlib configparser (no external deps,
# consistent with aiobi-term's stdlib-only contract). INI was chosen
# over JSON because the file is meant to be hand-edited by whoever
# owns the Aïobi build (comments are natural in INI; JSON has none).

from __future__ import annotations

import configparser
from dataclasses import dataclass, field
from pathlib import Path

CONFIG_PATH = Path("/etc/aiobi/update.conf")

# Fallback blacklist applied only if the config file is missing or the
# [blacklist] section is empty — mirrors the packages aos-debloat.service
# purges at first boot plus the Ubuntu native update GUIs aiobi-update
# replaces, so a missing config never leaves those reinstallable via a
# silent dist-upgrade.
_DEFAULT_BLACKLIST = frozenset({
    "snapd", "snap-confine", "snapd-desktop-integration",
    "apport", "whoopsie", "ubuntu-report",
    "popularity-contest", "apport-symptoms",
    "update-manager", "update-manager-core",
    "update-notifier", "update-notifier-common",
    "software-properties-gtk",
})


class PolicyError(Exception):
    """Raised when /etc/aiobi/update.conf exists but cannot be parsed
    into a usable policy. Maps to CLI exit code 10 (config error)."""


@dataclass
class Policy:
    check_cron: str = "weekly-sunday-0600"
    security_cron: str = "daily-0300"
    auto_apply_security: bool = True
    auto_apply_all: bool = False
    blacklist: frozenset[str] = field(default_factory=lambda: _DEFAULT_BLACKLIST)
    silent_check: bool = True
    show_progress: bool = True
    show_summary: bool = True


def _get_bool(parser: configparser.ConfigParser, section: str, key: str, default: bool) -> bool:
    if not parser.has_option(section, key):
        return default
    try:
        return parser.getboolean(section, key)
    except ValueError as exc:
        raise PolicyError(
            f"{CONFIG_PATH}: [{section}] {key} is not a valid boolean"
        ) from exc


def load_policy(path: Path = CONFIG_PATH) -> Policy:
    """Load /etc/aiobi/update.conf. Missing file -> defaults (not an
    error: aiobi-update must be usable out of the box). Present-but-
    malformed file -> PolicyError, which the CLI maps to exit code 10
    so a broken config is visible rather than silently ignored."""
    if not path.exists():
        return Policy()

    parser = configparser.ConfigParser(inline_comment_prefixes=("#",))
    try:
        parser.read(path, encoding="utf-8")
    except configparser.Error as exc:
        raise PolicyError(f"{path}: {exc}") from exc

    check_cron = parser.get("cadence", "check_cron", fallback="weekly-sunday-0600")
    security_cron = parser.get("cadence", "security_cron", fallback="daily-0300")
    auto_apply_security = _get_bool(parser, "cadence", "auto_apply_security", True)
    auto_apply_all = _get_bool(parser, "cadence", "auto_apply_all", False)

    raw_blacklist = parser.get("blacklist", "packages", fallback="")
    parsed_blacklist = {pkg.strip() for pkg in raw_blacklist.split(",") if pkg.strip()}
    blacklist = frozenset(parsed_blacklist) if parsed_blacklist else _DEFAULT_BLACKLIST

    silent_check = _get_bool(parser, "notify", "silent_check", True)
    show_progress = _get_bool(parser, "notify", "show_progress", True)
    show_summary = _get_bool(parser, "notify", "show_summary", True)

    return Policy(
        check_cron=check_cron,
        security_cron=security_cron,
        auto_apply_security=auto_apply_security,
        auto_apply_all=auto_apply_all,
        blacklist=blacklist,
        silent_check=silent_check,
        show_progress=show_progress,
        show_summary=show_summary,
    )
