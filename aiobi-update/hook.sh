#!/bin/sh
# Aïobi OS — APT DPkg hook logger for aiobi-update audit trail.
#
# Invoked from /etc/apt/apt.conf.d/52-aiobi-update-hooks as:
#   DPkg::Pre-Invoke  { "/usr/local/lib/aiobi-update/hook.sh pre";  };
#   DPkg::Post-Invoke { "/usr/local/lib/aiobi-update/hook.sh post"; };
#
# Delegating the log line to a shell script avoids APT config parser
# edge cases with nested \" quoting and $() subshells that would
# otherwise fail with "Extra junk after value".
#
# Never fails the enclosing apt transaction (all output redirected,
# `|| true` fallback).

phase="${1:-unknown}"

{
    printf '%s apt/dpkg transaction %s (uid=%s)\n' \
        "$(date -u +%FT%TZ)" \
        "$phase" \
        "$(id -u)"
} >> /var/log/aiobi-update.log 2>/dev/null || true
