# aiobi_update.state — JSON state file read/write.
#
# The state file is the single source of truth read by:
#   * `aiobi-update` (no args)        — status line
#   * `aiobi-update --notify-user`    — decides whether to notify and with
#                                       what count
#   * aiobi-update-notify.path        — watches for /run/aiobi-update/notify,
#                                       which is only a trigger flag, never
#                                       read for content
#
# Kept deliberately small: no schema versioning, no migrations — a
# single flat JSON document is durable enough for a local system state
# file and stdlib-json round-trips it without any dependency.

from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path

STATE_DIR = Path("/var/lib/aiobi-update")
STATE_FILE = STATE_DIR / "state.json"
DEFERRED_FILE = STATE_DIR / "deferred_until"


def utc_now_iso() -> str:
    """Return the current UTC time as an ISO-8601 string with minute
    precision (matches the "YYYY-MM-DDTHH:MM" shape used in --status
    output and in notifications)."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M")


@dataclass
class UpdateState:
    last_check: str | None = None
    updates_available: int = 0
    packages: list[str] = field(default_factory=list)
    last_apply: str | None = None
    last_apply_result: str | None = None  # "success" | "partial" | "failed" | None
    reboot_required: bool = False

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> "UpdateState":
        known = {f for f in cls.__dataclass_fields__}
        return cls(**{k: v for k, v in data.items() if k in known})


def load() -> UpdateState:
    """Read state.json. Missing or corrupt file yields a fresh, empty
    state rather than raising — a first run or a stale/partial write
    should never crash the CLI's status path."""
    if not STATE_FILE.exists():
        return UpdateState()
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as fh:
            return UpdateState.from_dict(json.load(fh))
    except (json.JSONDecodeError, OSError, TypeError):
        return UpdateState()


def save(state: UpdateState) -> None:
    """Write state.json atomically (write to a temp file in the same
    directory, then os.replace) so a crash mid-write never leaves a
    truncated state file behind."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp_path = STATE_FILE.with_suffix(".json.tmp")
    with open(tmp_path, "w", encoding="utf-8") as fh:
        json.dump(state.to_dict(), fh, indent=2)
        fh.write("\n")
    os.replace(tmp_path, STATE_FILE)


def write_deferred_until(deferred_iso: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    DEFERRED_FILE.write_text(deferred_iso + "\n", encoding="utf-8")


def read_deferred_until() -> datetime | None:
    if not DEFERRED_FILE.exists():
        return None
    try:
        text = DEFERRED_FILE.read_text(encoding="utf-8").strip()
        return datetime.fromisoformat(text)
    except (ValueError, OSError):
        return None


def is_deferred(now: datetime | None = None) -> bool:
    """True when a --defer window set by the user has not yet elapsed."""
    until = read_deferred_until()
    if until is None:
        return False
    now = now or datetime.now(timezone.utc)
    if until.tzinfo is None:
        until = until.replace(tzinfo=timezone.utc)
    return now < until
