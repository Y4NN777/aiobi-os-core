#!/usr/bin/env bash
# =============================================================================
# Test — Step 11 — APT brand alias (cosmetic mirror rename)
# =============================================================================
# Verifies that /etc/hosts carries the mirror.aiobi.local alias, that the
# DEB822 apt sources file (Ubuntu 24.04 default location) has been rewritten
# to reference the alias instead of the Canonical hostname, and that a
# .aiobi.bak snapshot of the original file exists (idempotency guarantee).
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 11 — APT mirror hostname soft-branded to mirror.aiobi.local"

assert_file /etc/hosts
assert_grep /etc/hosts "mirror.aiobi.local"
assert_grep /etc/hosts "security.aiobi.local"

DEB822=/etc/apt/sources.list.d/ubuntu.sources
if [ -f "$DEB822" ]; then
    assert_grep "$DEB822" "mirror.aiobi.local"
    assert_no_grep "$DEB822" "bf.archive.ubuntu.com"
    # Backup of the original vendor file — proves the sed pass ran.
    assert_file "${DEB822}.aiobi.bak"
else
    skip "DEB822 sources file rewritten" "$DEB822 not present on this base"
fi

finalize
