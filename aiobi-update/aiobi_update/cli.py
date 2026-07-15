# aiobi_update.cli — argparse dispatcher.
#
# Exit codes (per agreed spec)
#   0  success
#   1  no updates available
#   2  partial (some packages failed to apply)
#   3  apt/dpkg lock held by another process
#   10 config error (/etc/aiobi/update.conf malformed)
#
# Modes
#   (no args)         status: reads state.json, prints count + last check
#   --check           apt-get update -qq + count upgradable + write state;
#                     touches /run/aiobi-update/notify when policy allows
#                     silent notification and count > 0
#   --apply [-y]      confirm (GTK, unless -y) -> progress (GTK) -> apply
#                     -> summary (GTK, unless policy disables it)
#   --apply --security-only [-y]
#                     internal path used by aiobi-update-apply.service when
#                     triggered by aiobi-update-security.timer (see
#                     ASSUMPTIONS in the install script header) — restricts
#                     the transaction to the noble-security suite and never
#                     raises a GTK popup (it runs at 03:00 with no session
#                     guaranteed to be present)
#   --defer 24h       write /var/lib/aiobi-update/deferred_until
#   --notify-user     read state.json, notify-send with action buttons
#                     (invoked by aiobi-update-notify.service, a systemd
#                     --user unit — see etc/systemd/user/)
#   --log             tail /var/log/aiobi-update.log
#   --version         print __version__

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

from . import __version__
from . import apt
from . import notify
from . import policy as policy_mod
from . import state as state_mod

LOG_FILE = "/var/log/aiobi-update.log"
NOTIFY_TRIGGER = "/run/aiobi-update/notify"

EXIT_OK = 0
EXIT_NO_UPDATES = 1
EXIT_PARTIAL = 2
EXIT_LOCK_HELD = 3
EXIT_CONFIG_ERROR = 10

_DEFER_PATTERN = re.compile(r"^(\d+)\s*([hHdD])$")


def _log(message: str) -> None:
    """Append a timestamped line to /var/log/aiobi-update.log. Rotated
    by etc/logrotate.d/aiobi-update. Best-effort: a logging failure
    (e.g. read-only /var/log during a chroot smoke test) must never
    crash the CLI."""
    line = f"{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')} {message}\n"
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as fh:
            fh.write(line)
    except OSError:
        pass


def _parse_defer(value: str) -> timedelta:
    match = _DEFER_PATTERN.match(value.strip())
    if not match:
        raise ValueError(f"invalid --defer value: {value!r} (expected e.g. '24h' or '2d')")
    amount, unit = int(match.group(1)), match.group(2).lower()
    return timedelta(hours=amount) if unit == "h" else timedelta(days=amount)


def cmd_status(_args: argparse.Namespace) -> int:
    st = state_mod.load()
    last_check = st.last_check or "never"
    print(f"{st.updates_available} updates dispo, last check {last_check}")
    if st.reboot_required:
        print("Reboot required to finish applying a previous update.")
    return EXIT_OK


def cmd_check(_args: argparse.Namespace) -> int:
    try:
        pol = policy_mod.load_policy()
    except policy_mod.PolicyError as exc:
        _log(f"--check config error: {exc}")
        print(f"aiobi-update: config error: {exc}", file=sys.stderr)
        return EXIT_CONFIG_ERROR

    try:
        apt.apt_update()
        packages = apt.list_upgradable(blacklist=pol.blacklist)
    except apt.AptLockError as exc:
        _log(f"--check: apt lock held: {exc}")
        print("aiobi-update: apt/dpkg lock held by another process", file=sys.stderr)
        return EXIT_LOCK_HELD
    except apt.AptError as exc:
        _log(f"--check: apt-get update failed: {exc}")
        notify.notify_error(str(exc))
        print(f"aiobi-update: {exc}", file=sys.stderr)
        return EXIT_PARTIAL

    st = state_mod.load()
    st.last_check = state_mod.utc_now_iso()
    st.updates_available = len(packages)
    st.packages = packages
    st.reboot_required = apt.reboot_required()
    state_mod.save(st)
    _log(f"--check: {len(packages)} upgradable package(s) found")

    if packages and pol.silent_check:
        try:
            import os
            os.makedirs("/run/aiobi-update", exist_ok=True)
            with open(NOTIFY_TRIGGER, "a", encoding="utf-8"):
                os.utime(NOTIFY_TRIGGER, None)
        except OSError as exc:
            _log(f"--check: could not touch {NOTIFY_TRIGGER}: {exc}")

    if st.reboot_required:
        notify.notify_reboot_required()

    print(f"{len(packages)} updates dispo, last check {st.last_check}")
    return EXIT_OK if packages else EXIT_NO_UPDATES


def _do_apply(pol, packages: list[str], assume_yes: bool, show_gui: bool):
    """Shared apply path for the interactive (--apply) and, if ever
    invoked without --security-only, non-security automated path.
    Returns (succeeded, failed)."""
    from . import popup  # imported lazily: GTK is only needed here

    if show_gui and not assume_yes:
        if not popup.confirm(len(packages)):
            _log("--apply: cancelled by user at confirm dialog")
            return [], []

    def worker():
        succeeded, failed = apt.upgrade_packages(packages)
        return popup.ApplyResult(succeeded, failed, apt.reboot_required())

    if show_gui and pol.show_progress:
        result = popup.run_with_progress(worker)
        succeeded, failed = result.succeeded, result.failed
    else:
        succeeded, failed = apt.upgrade_packages(packages)

    if show_gui and pol.show_summary:
        popup.summary(succeeded, failed, apt.reboot_required())

    return succeeded, failed


def cmd_apply(args: argparse.Namespace) -> int:
    try:
        pol = policy_mod.load_policy()
    except policy_mod.PolicyError as exc:
        _log(f"--apply config error: {exc}")
        print(f"aiobi-update: config error: {exc}", file=sys.stderr)
        return EXIT_CONFIG_ERROR

    show_gui = not args.yes

    if args.security_only:
        # Automated overnight path (aiobi-update-apply.service triggered
        # by aiobi-update-security.timer). No GTK popup: this can run
        # with no logged-in session at 03:00.
        try:
            result = apt.upgrade_security_only()
        except apt.AptLockError as exc:
            _log(f"--apply --security-only: apt lock held: {exc}")
            return EXIT_LOCK_HELD
        st = state_mod.load()
        st.last_apply = state_mod.utc_now_iso()
        st.reboot_required = apt.reboot_required()
        if result.returncode == 0:
            st.last_apply_result = "success"
            state_mod.save(st)
            _log("--apply --security-only: completed")
            if st.reboot_required:
                notify.notify_reboot_required()
            return EXIT_OK
        st.last_apply_result = "partial"
        state_mod.save(st)
        _log(f"--apply --security-only: apt-get exited {result.returncode}: {result.stderr.strip()}")
        notify.notify_error("Security-only update failed — see /var/log/aiobi-update.log")
        return EXIT_PARTIAL

    try:
        apt.apt_update()
        packages = apt.list_upgradable(blacklist=pol.blacklist)
    except apt.AptLockError as exc:
        _log(f"--apply: apt lock held: {exc}")
        print("aiobi-update: apt/dpkg lock held by another process", file=sys.stderr)
        return EXIT_LOCK_HELD
    except apt.AptError as exc:
        _log(f"--apply: apt-get update failed: {exc}")
        print(f"aiobi-update: {exc}", file=sys.stderr)
        return EXIT_PARTIAL

    if not packages:
        print("aiobi-update: no updates available")
        return EXIT_NO_UPDATES

    try:
        succeeded, failed = _do_apply(pol, packages, args.yes, show_gui)
    except apt.AptLockError as exc:
        _log(f"--apply: apt lock held mid-transaction: {exc}")
        return EXIT_LOCK_HELD

    st = state_mod.load()
    st.last_apply = state_mod.utc_now_iso()
    st.reboot_required = apt.reboot_required()
    if not succeeded and not failed:
        # user cancelled at the confirm dialog
        state_mod.save(st)
        return EXIT_OK
    st.last_apply_result = "partial" if failed else "success"
    st.updates_available = len(failed)
    st.packages = failed
    state_mod.save(st)
    _log(f"--apply: {len(succeeded)} succeeded, {len(failed)} failed")

    if st.reboot_required:
        notify.notify_reboot_required()

    if failed:
        print(f"aiobi-update: {len(succeeded)} succeeded, {len(failed)} failed: {', '.join(failed)}")
        return EXIT_PARTIAL

    print(f"aiobi-update: {len(succeeded)} package(s) updated")
    return EXIT_OK


def cmd_defer(args: argparse.Namespace) -> int:
    try:
        delta = _parse_defer(args.defer)
    except ValueError as exc:
        print(f"aiobi-update: {exc}", file=sys.stderr)
        return EXIT_CONFIG_ERROR
    until = datetime.now(timezone.utc) + delta
    state_mod.write_deferred_until(until.isoformat())
    _log(f"--defer: deferred until {until.isoformat()}")
    print(f"aiobi-update: deferred until {until.strftime('%Y-%m-%dT%H:%M')}")
    return EXIT_OK


def cmd_notify_user(_args: argparse.Namespace) -> int:
    """Invoked by aiobi-update-notify.service (systemd --user), which is
    itself triggered by aiobi-update-notify.path watching
    /run/aiobi-update/notify. Runs inside the user session already, so
    no DBUS_SESSION_BUS_ADDRESS bridging is needed."""
    if state_mod.is_deferred():
        return EXIT_OK
    st = state_mod.load()
    if st.updates_available <= 0:
        return EXIT_NO_UPDATES
    chosen = notify.notify_updates_available(st.updates_available)
    if chosen == "apply":
        subprocess.Popen(["/usr/local/bin/aiobi-update", "--apply"])
    elif chosen == "defer":
        subprocess.run(["/usr/local/bin/aiobi-update", "--defer", "24h"])
    return EXIT_OK


def cmd_log(_args: argparse.Namespace) -> int:
    try:
        with open(LOG_FILE, "r", encoding="utf-8") as fh:
            lines = fh.readlines()
    except OSError as exc:
        print(f"aiobi-update: cannot read {LOG_FILE}: {exc}", file=sys.stderr)
        return EXIT_CONFIG_ERROR
    for line in lines[-200:]:
        print(line, end="")
    return EXIT_OK


def cmd_version(_args: argparse.Namespace) -> int:
    print(f"aiobi-update {__version__}")
    return EXIT_OK


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="aiobi-update",
        description=(
            "Aïobi OS native update mechanism — replaces Ubuntu's "
            "update-manager, which fails on Aïobi due to purged "
            "apport/whoopsie dependencies and carries no Aïobi branding."
        ),
    )
    parser.add_argument("--check", action="store_true",
                        help="Force apt-get update -qq, count upgradable packages, write state.")
    parser.add_argument("--apply", action="store_true",
                        help="Apply available updates (excluding the blacklist), "
                             "after a GTK confirmation unless -y is given.")
    parser.add_argument("-y", "--yes", action="store_true",
                        help="Non-interactive --apply (no confirm/summary popups). "
                             "Used by aiobi-update-apply.service.")
    parser.add_argument("--security-only", action="store_true",
                        help="With --apply: restrict the transaction to the "
                             "noble-security suite and skip all GTK popups. "
                             "Used by the overnight auto-apply-security path.")
    parser.add_argument("--defer", metavar="DURATION",
                        help="Defer notifications for DURATION, e.g. '24h' or '2d'.")
    parser.add_argument("--notify-user", action="store_true",
                        help="Internal: read state.json and notify-send the "
                             "current user (invoked by aiobi-update-notify.service).")
    parser.add_argument("--log", action="store_true",
                        help="Tail /var/log/aiobi-update.log.")
    parser.add_argument("--version", action="store_true",
                        help="Print the aiobi-update version.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.version:
        return cmd_version(args)
    if args.log:
        return cmd_log(args)
    if args.defer:
        return cmd_defer(args)
    if args.notify_user:
        return cmd_notify_user(args)
    if args.apply:
        return cmd_apply(args)
    if args.check:
        return cmd_check(args)
    return cmd_status(args)


if __name__ == "__main__":
    sys.exit(main())
