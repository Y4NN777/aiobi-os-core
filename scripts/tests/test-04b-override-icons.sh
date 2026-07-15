#!/usr/bin/env bash
# =============================================================================
# Test — Step 04b — AI-native SVG placeholders readable
# =============================================================================
# Verifies that the five AI-oriented placeholder SVGs installed by either
# script 04 or script 04b are present, non-empty, and parseable as XML/SVG
# (opening <svg tag on the first useful line).
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 04b — AI-native icon overrides installed and readable"

AIOBI_ICON_DIR="/usr/share/icons/Aiobi/scalable/apps"

ICONS=(
    aiobi-ai-chat
    aiobi-ai-terminal
    aiobi-ai-secure-status
    aiobi-firewall-status
    aiobi-start-menu
)

for name in "${ICONS[@]}"; do
    svg="$AIOBI_ICON_DIR/${name}.svg"
    if [ ! -f "$svg" ]; then
        fail "AI-native SVG readable: $name" "file missing"
        continue
    fi
    if [ ! -s "$svg" ]; then
        fail "AI-native SVG readable: $name" "file is empty"
        continue
    fi
    if grep -q "<svg" "$svg" 2>/dev/null; then
        pass "AI-native SVG readable: $name"
    else
        fail "AI-native SVG readable: $name" "no <svg element in file"
    fi
done

finalize
