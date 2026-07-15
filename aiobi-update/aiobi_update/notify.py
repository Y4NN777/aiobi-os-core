# aiobi_update.notify — notify-send helpers (silent, non-interactive alerts).
#
# Used for: updates-available heads-up, reboot-required flag, and error
# alerts. Interactive confirmation / progress / summary UI lives in
# popup.py (GTK4 + libadwaita) — notify-send is for the passive channel
# only, per the agreed notification-flow split.
#
# Runs in the user session (this module is only ever invoked from
# aiobi-update-notify.service, a systemd --user unit — see the
# no-DBUS-bridging note in etc/systemd/user/aiobi-update-notify.service),
# so DISPLAY / DBUS_SESSION_BUS_ADDRESS are already correct and no
# `sudo -u <user>` / `/run/user/<uid>/bus` plumbing is needed here.

from __future__ import annotations

import shutil
import subprocess

APP_NAME = "Aïobi OS"
ICON = "software-update-available"


def _notify_send_available() -> bool:
    return shutil.which("notify-send") is not None


def notify(summary: str, body: str = "", urgency: str = "normal",
           icon: str = ICON, actions: dict[str, str] | None = None) -> str | None:
    """Send a desktop notification. Returns the chosen action key when
    the notification server supports action buttons and the user picks
    one (best-effort — many notification daemons render notify-send
    without actionable buttons); returns None otherwise.

    actions: mapping of {action_key: label}, e.g. {"apply": "Update now",
    "defer": "Remind me later"}."""
    if not _notify_send_available():
        return None

    cmd = [
        "notify-send",
        "--app-name", APP_NAME,
        "--icon", icon,
        "--urgency", urgency,
    ]
    if actions:
        for key, label in actions.items():
            cmd += ["--action", f"{key}={label}"]
        cmd += ["--wait"]
    cmd += [summary, body]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except (subprocess.SubprocessError, OSError):
        return None

    chosen = result.stdout.strip()
    return chosen or None


def notify_updates_available(count: int) -> str | None:
    return notify(
        f"{APP_NAME} — {count} update{'s' if count != 1 else ''} available",
        "A weekly check found packages ready to install.",
        actions={"apply": "Update now", "defer": "Remind me later"},
    )


def notify_reboot_required() -> None:
    notify(
        f"{APP_NAME} — reboot required",
        "A kernel or core library update needs a reboot to take effect.",
        urgency="critical",
        icon="system-reboot",
    )


def notify_error(message: str) -> None:
    notify(
        f"{APP_NAME} — update error",
        message,
        urgency="critical",
        icon="dialog-error",
    )
