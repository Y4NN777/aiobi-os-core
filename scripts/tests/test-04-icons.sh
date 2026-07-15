#!/usr/bin/env bash
# =============================================================================
# Test — Step 04 — Icon theme (Papirus + Aïobi placeholders)
# =============================================================================
# Verifies that both Papirus flavours are installed, that the Aïobi
# placeholder theme is present under /usr/share/icons/Aiobi with all five
# expected SVGs, and that the Papirus backup tree is preserved.
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 04 — Papirus + Aïobi placeholder icons"

assert_pkg "papirus-icon-theme"
assert_dir "/usr/share/icons/Papirus"
assert_dir "/usr/share/icons/Papirus-Dark"

# Aïobi placeholder theme metadata + SVGs.
AIOBI_ICON_DIR="/usr/share/icons/Aiobi"
assert_dir "$AIOBI_ICON_DIR"
assert_file "$AIOBI_ICON_DIR/index.theme"
assert_dir "$AIOBI_ICON_DIR/scalable/apps"

for name in aiobi-start-menu aiobi-ai-terminal aiobi-ai-chat aiobi-ai-secure-status aiobi-firewall-status; do
    assert_file "$AIOBI_ICON_DIR/scalable/apps/${name}.svg"
done

# Papirus safety backup — script 04 preserves originals here for rollback.
assert_dir "/usr/share/icons/Papirus-Aiobi-backup"

finalize
