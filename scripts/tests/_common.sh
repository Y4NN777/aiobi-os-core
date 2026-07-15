#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Test harness shared helpers
# =============================================================================
# Sourced by every scripts/tests/test-*.sh file — do not execute directly.
#
# Provides:
#   - Colour-safe PASS / FAIL / SKIP reporters with running counters
#   - Assertion helpers (files, dirs, packages, binaries, greps, systemd units,
#     kernel firewall rules)
#   - finalize() that prints per-test summary and exits with a status derived
#     from the FAIL count (0 = all PASS, 1 = at least one FAIL — SKIP is not
#     failure)
#
# Design notes:
#   - Colour output is stripped when stdout is not a TTY (harness capture,
#     CI logs) so failures are still readable.
#   - Every helper is side-effect free apart from the counters. Tests can
#     freely reorder or repeat calls.
#   - Chroot-tolerance is implemented at the CALLER level via the
#     have_systemd() and have_ai_daemon() predicates — helpers below never
#     assume systemd is running or that a network is reachable.
# =============================================================================

# Counters + failure list shared across every helper call in one test run.
TESTS_PASS=0
TESTS_FAIL=0
TESTS_SKIP=0
FAILED_CHECKS=()

# Colours only when writing to a real TTY (or when FORCE_COLOR=1). Falls back
# to plain text under `bash "$test" > log` from the harness, keeping the
# aggregated summary parseable.
if [ -t 1 ] || [ "${FORCE_COLOR:-0}" = "1" ]; then
    _C_GREEN=$'\033[32m'
    _C_RED=$'\033[31m'
    _C_YELLOW=$'\033[33m'
    _C_RESET=$'\033[0m'
else
    _C_GREEN=""
    _C_RED=""
    _C_YELLOW=""
    _C_RESET=""
fi

# ----- reporters -------------------------------------------------------------

pass() {
    TESTS_PASS=$((TESTS_PASS + 1))
    printf '  %sPASS%s  %s\n' "$_C_GREEN" "$_C_RESET" "$1"
}

fail() {
    TESTS_FAIL=$((TESTS_FAIL + 1))
    FAILED_CHECKS+=("$1 — $2")
    printf '  %sFAIL%s  %s — %s\n' "$_C_RED" "$_C_RESET" "$1" "$2"
}

skip() {
    TESTS_SKIP=$((TESTS_SKIP + 1))
    printf '  %sSKIP%s  %s — %s\n' "$_C_YELLOW" "$_C_RESET" "$1" "$2"
}

# ----- filesystem assertions -------------------------------------------------

assert_file() {
    if [ -f "$1" ]; then
        pass "file exists: $1"
    else
        fail "file exists: $1" "not found"
    fi
}

assert_no_file() {
    if [ -f "$1" ]; then
        fail "file absent: $1" "unexpectedly present"
    else
        pass "file absent: $1"
    fi
}

assert_dir() {
    if [ -d "$1" ]; then
        pass "dir exists: $1"
    else
        fail "dir exists: $1" "not found"
    fi
}

assert_no_dir() {
    if [ -d "$1" ]; then
        fail "dir absent: $1" "unexpectedly present"
    else
        pass "dir absent: $1"
    fi
}

assert_executable() {
    if [ -x "$1" ]; then
        pass "executable: $1"
    else
        fail "executable: $1" "not executable or missing"
    fi
}

# ----- content assertions ----------------------------------------------------

# assert_grep <file> <fixed-string>
# Passes when the fixed string is present in the file.
assert_grep() {
    if [ -f "$1" ] && grep -qF -- "$2" "$1" 2>/dev/null; then
        pass "$1 contains '$2'"
    else
        fail "$1 contains '$2'" "not found"
    fi
}

# assert_no_grep <file> <fixed-string>
# Passes when the fixed string is NOT present in the file (or file missing).
assert_no_grep() {
    if [ -f "$1" ] && grep -qF -- "$2" "$1" 2>/dev/null; then
        fail "$1 does not contain '$2'" "unexpectedly present"
    else
        pass "$1 does not contain '$2'"
    fi
}

# assert_grep_regex <file> <ERE pattern>
assert_grep_regex() {
    if [ -f "$1" ] && grep -qE -- "$2" "$1" 2>/dev/null; then
        pass "$1 matches /$2/"
    else
        fail "$1 matches /$2/" "no match"
    fi
}

# ----- binary / package assertions ------------------------------------------

assert_binary() {
    if command -v "$1" >/dev/null 2>&1; then
        pass "binary on PATH: $1"
    else
        fail "binary on PATH: $1" "not found"
    fi
}

assert_no_binary() {
    if command -v "$1" >/dev/null 2>&1; then
        fail "binary absent: $1" "unexpectedly present"
    else
        pass "binary absent: $1"
    fi
}

assert_pkg() {
    if dpkg -s "$1" >/dev/null 2>&1; then
        pass "package installed: $1"
    else
        fail "package installed: $1" "not installed"
    fi
}

assert_no_pkg() {
    if dpkg -s "$1" >/dev/null 2>&1; then
        fail "package absent: $1" "unexpectedly installed"
    else
        pass "package absent: $1"
    fi
}

# assert_flatpak <ref-prefix>   e.g. md.obsidian.Obsidian
assert_flatpak() {
    if command -v flatpak >/dev/null 2>&1 \
       && flatpak list --columns=ref 2>/dev/null \
          | awk -F/ '{print $1}' | grep -Fxq "$1"; then
        pass "flatpak installed: $1"
    else
        fail "flatpak installed: $1" "not installed"
    fi
}

assert_no_flatpak() {
    if command -v flatpak >/dev/null 2>&1 \
       && flatpak list --columns=ref 2>/dev/null \
          | awk -F/ '{print $1}' | grep -Fxq "$1"; then
        fail "flatpak absent: $1" "unexpectedly installed"
    else
        pass "flatpak absent: $1"
    fi
}

# ----- systemd assertions ----------------------------------------------------

# assert_systemd_unit <unit-file-path>
# Only checks that the unit FILE is present. Whether the unit is active is a
# runtime concern verified elsewhere (and skipped in chroot).
assert_systemd_unit() {
    assert_file "$1"
}

# ----- environment predicates ------------------------------------------------

# have_systemd: true if the harness is running on a live systemd host.
# Absence of /run/systemd/system is the canonical chroot signal.
have_systemd() {
    [ -d /run/systemd/system ]
}

# have_ai_daemon: true if the local Ollama API is reachable on the loopback
# proxy socket.
have_ai_daemon() {
    curl -sf --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1
}

# ----- finalisation ----------------------------------------------------------

finalize() {
    local total=$((TESTS_PASS + TESTS_FAIL + TESTS_SKIP))
    printf '\n  -- %s --\n' "${TEST_TITLE:-untitled}"
    printf '     %d PASS  %d FAIL  %d SKIP  (%d total)\n' \
        "$TESTS_PASS" "$TESTS_FAIL" "$TESTS_SKIP" "$total"
    if [ "$TESTS_FAIL" -gt 0 ]; then
        printf '     Failing checks:\n'
        local c
        for c in "${FAILED_CHECKS[@]}"; do
            printf '       - %s\n' "$c"
        done
        exit 1
    fi
    exit 0
}
