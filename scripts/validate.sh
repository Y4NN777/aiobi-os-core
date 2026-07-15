#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Validation harness (per-domain test aggregator)
# =============================================================================
# The harness is intentionally unnumbered: it is a meta-tool that iterates
# over scripts/tests/*.sh, not a numbered step in the customisation pipeline.
# (Same reason run-all.sh has no numeric prefix.)
#
# Runs every scripts/tests/test-*.sh in filename order, captures PASS / FAIL /
# SKIP counts across all of them, prints a per-test result line + a final
# summary block. Exits 0 when no test reports a FAIL, 1 otherwise. SKIP does
# NOT count as failure — a chroot-only run may legitimately skip live-systemd
# assertions, and a build-host run without an AI daemon will skip the runtime
# probes.
#
# Design notes:
#   - Every domain check that used to live inline in the earlier numbered
#     validate script has been extracted into a scripts/tests/test-*.sh
#     file. This harness itself no longer holds any per-domain logic:
#     adding a new test is a drop-in operation, no touching this file
#     required.
#   - Each test is executed under a fresh bash process (`bash "$test"`) so
#     that a test that calls `exit 1` in finalize() only fails itself, not
#     the harness. The harness aggregates from the CHILD exit codes.
#   - The per-test output is streamed live so a stuck test is visible.
#   - The summary block is emitted on stdout in a shape a downstream CI
#     job can regex on: `=== Results: X/Y PASS[, N FAIL: ...] ===`.
#
# Backward compatibility:
#   The exit-code contract of the old numbered validate script is preserved
#   — 0 on all PASS, non-zero on any FAIL. Any wrapper that invoked the
#   validator through the numbered filename must be updated to call
#   `bash scripts/validate.sh` (run-all.sh has been updated already).
# =============================================================================

set -u

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)/tests"
COMMON="$TESTS_DIR/_common.sh"

if [ ! -d "$TESTS_DIR" ]; then
    echo "ERROR: tests directory missing: $TESTS_DIR"
    exit 2
fi
if [ ! -f "$COMMON" ]; then
    echo "ERROR: shared helpers missing: $COMMON"
    exit 2
fi

# Colours only when writing to a real TTY.
if [ -t 1 ]; then
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_YELLOW=$'\033[33m'
    C_BOLD=$'\033[1m'
    C_RESET=$'\033[0m'
else
    C_GREEN=""; C_RED=""; C_YELLOW=""; C_BOLD=""; C_RESET=""
fi

printf '%s===== Aïobi OS validation — running tests from %s =====%s\n' \
    "$C_BOLD" "$TESTS_DIR" "$C_RESET"

# Enumerate tests in filename order, excluding the shared helpers.
mapfile -t TESTS < <(
    find "$TESTS_DIR" -maxdepth 1 -type f -name 'test-*.sh' | sort
)

if [ "${#TESTS[@]}" -eq 0 ]; then
    echo "ERROR: no test files found under $TESTS_DIR (looked for test-*.sh)"
    exit 2
fi

RUN_TOTAL=0
RUN_OK=0
RUN_FAIL=0
FAILED_TESTS=()

for test in "${TESTS[@]}"; do
    RUN_TOTAL=$((RUN_TOTAL + 1))
    name=$(basename "$test")
    printf '\n%s>>> %s%s\n' "$C_BOLD" "$name" "$C_RESET"

    # Run each test in a fresh bash process so that finalize()'s `exit 1`
    # only fails that test, not the harness. `set +e` around the call so
    # a failing child exit code doesn't abort the loop under `set -e`
    # (though we're already in `set -u` only, not `set -e`).
    if bash "$test"; then
        RUN_OK=$((RUN_OK + 1))
        printf '%s>>> %s: PASS%s\n' "$C_GREEN" "$name" "$C_RESET"
    else
        RUN_FAIL=$((RUN_FAIL + 1))
        FAILED_TESTS+=("$name")
        printf '%s>>> %s: FAIL%s\n' "$C_RED" "$name" "$C_RESET"
    fi
done

printf '\n%s===== Results: %d/%d PASS' "$C_BOLD" "$RUN_OK" "$RUN_TOTAL"
if [ "$RUN_FAIL" -gt 0 ]; then
    printf ', %d FAIL: %s' "$RUN_FAIL" "$(IFS=,; echo "${FAILED_TESTS[*]}")"
fi
printf ' =====%s\n' "$C_RESET"

if [ "$RUN_FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
