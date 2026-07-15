#!/bin/bash
# Aïobi OS — apply-helper.sh
#
# Executed as root via `pkexec` from aiobi_update.cli's PKEXEC MODE
# (user + GUI session, non-systemd, no -y). Never invoked directly by
# a human — cli.py builds the exact argv.
#
# Contract (see /tmp scratchpad report / task spec — mirrored here for
# on-host readers):
#   argv        : apply-helper.sh [--security-only]
#   stdout      : AIOBI-PROGRESS: <n>/<total> <pkgname>   before each
#                 package upgrade attempt
#                 AIOBI-FAILED: <pkgname>                 on a single
#                 package's apt-get failure (non-lock)
#                 AIOBI-DONE: succeeded=N failed=M        once, at the end
#   exit codes  : 0  all succeeded (or nothing to do)
#                 2  partial (one or more packages failed)
#                 3  apt/dpkg lock held by another process
#                 10 config error (/etc/aiobi/update.conf malformed or
#                    apt-get update itself failed for a non-lock reason)
#
# pkexec sanitises the environment before exec — no DISPLAY, no
# inherited PATH beyond a safe default. This script therefore uses only
# absolute /usr/bin paths and sets its own DEBIAN_FRONTEND, and makes no
# assumption about a GUI/session being reachable from here (popup.py on
# the caller side owns all UI; this process only ever writes to stdout).

set -uo pipefail

export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

CONF_FILE="/etc/aiobi/update.conf"
APT_GET="/usr/bin/apt-get"
APT="/usr/bin/apt"

SECURITY_ONLY=0
case "${1:-}" in
    --security-only)
        SECURITY_ONLY=1
        ;;
    "")
        ;;
    *)
        printf 'apply-helper: unknown argument: %s\n' "${1:-}" >&2
        exit 10
        ;;
esac

# Default blacklist mirrors aiobi_update.policy._DEFAULT_BLACKLIST —
# used only when /etc/aiobi/update.conf is absent or its [blacklist]
# section is empty, exactly like policy.py's own fallback.
DEFAULT_BLACKLIST="snapd, snap-confine, snapd-desktop-integration, apport, whoopsie, ubuntu-report, popularity-contest, apport-symptoms, update-manager, update-manager-core, update-notifier, update-notifier-common, software-properties-gtk"

_lock_held() {
    # Mirrors aiobi_update.apt._LOCK_PATTERNS.
    printf '%s' "$1" | grep -qiE \
        'Could not get lock|Unable to lock the administration directory|is another process using it'
}

# ----- Parse [blacklist] packages = a, b, c from update.conf ----------------
read_blacklist_raw() {
    if [ ! -f "$CONF_FILE" ]; then
        printf '%s\n' "$DEFAULT_BLACKLIST"
        return 0
    fi
    if [ ! -r "$CONF_FILE" ]; then
        printf 'apply-helper: %s exists but is not readable\n' "$CONF_FILE" >&2
        return 10
    fi

    local raw
    raw="$(awk '
        /^\[/ { insec = ($0 ~ /^\[blacklist\][[:space:]]*$/) }
        insec && $0 ~ /^[[:space:]]*packages[[:space:]]*=/ {
            sub(/^[[:space:]]*packages[[:space:]]*=[[:space:]]*/, "")
            print
            exit
        }
    ' "$CONF_FILE")"

    # Strip inline "# ..." comments the same way configparser's
    # inline_comment_prefixes=("#",) does in policy.py.
    raw="$(printf '%s' "$raw" | sed 's/#.*$//')"

    if [ -z "$(printf '%s' "$raw" | tr -d '[:space:]')" ]; then
        printf '%s\n' "$DEFAULT_BLACKLIST"
    else
        printf '%s\n' "$raw"
    fi
}

BLACKLIST_RAW="$(read_blacklist_raw)"
rc=$?
if [ "$rc" -eq 10 ]; then
    exit 10
fi

# Normalise to newline-separated, trimmed package names for a fast
# `grep -Fxq` membership test below.
BLACKLIST_FILE="$(mktemp)"
trap 'rm -f "$BLACKLIST_FILE"' EXIT
printf '%s' "$BLACKLIST_RAW" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' > "$BLACKLIST_FILE"

is_blacklisted() {
    grep -Fxq "$1" "$BLACKLIST_FILE"
}

# ----- apt-get update, then build the filtered upgradable list -------------
update_out="$("$APT_GET" update -qq 2>&1)"
update_rc=$?
if [ "$update_rc" -ne 0 ]; then
    if _lock_held "$update_out"; then
        printf 'apply-helper: apt lock held during update: %s\n' "$update_out" >&2
        exit 3
    fi
    printf 'apply-helper: apt-get update failed: %s\n' "$update_out" >&2
    exit 10
fi

list_out="$("$APT" list --upgradable 2>/dev/null)"

PACKAGES=()
while IFS= read -r line; do
    # "pkgname/suite version arch [upgradable from: ...]"
    pkg="${line%%/*}"
    [ "$pkg" = "$line" ] && continue  # no "/" -> not a package line
    suite_field="${line#*/}"
    suite="${suite_field%% *}"

    if [ "$SECURITY_ONLY" -eq 1 ] && [ "$suite" != "noble-security" ]; then
        continue
    fi
    if is_blacklisted "$pkg"; then
        continue
    fi
    PACKAGES+=("$pkg")
done <<< "$list_out"

TOTAL=${#PACKAGES[@]}

if [ "$TOTAL" -eq 0 ]; then
    printf 'AIOBI-DONE: succeeded=0 failed=0\n'
    exit 0
fi

# ----- Apply each package individually, streaming progress -----------------
succeeded=0
failed=0
n=0
for pkg in "${PACKAGES[@]}"; do
    n=$((n + 1))
    printf 'AIOBI-PROGRESS: %d/%d %s\n' "$n" "$TOTAL" "$pkg"

    install_out="$("$APT_GET" install --only-upgrade -y "$pkg" 2>&1)"
    install_rc=$?

    if [ "$install_rc" -eq 0 ]; then
        succeeded=$((succeeded + 1))
    else
        if _lock_held "$install_out"; then
            printf 'apply-helper: apt lock held mid-transaction: %s\n' "$install_out" >&2
            exit 3
        fi
        printf 'AIOBI-FAILED: %s\n' "$pkg"
        printf 'apply-helper: %s failed: %s\n' "$pkg" "$install_out" >&2
        failed=$((failed + 1))
    fi
done

printf 'AIOBI-DONE: succeeded=%d failed=%d\n' "$succeeded" "$failed"

if [ "$failed" -gt 0 ]; then
    exit 2
fi
exit 0
