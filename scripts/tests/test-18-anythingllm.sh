#!/usr/bin/env bash
# =============================================================================
# Test — Step 18 — AnythingLLM Desktop
# =============================================================================
# Verifies that the AnythingLLM AppImage was downloaded to /opt/aiobi/ and
# is executable, that the .desktop entry is in place, and that the /etc/skel
# preferences.json points at the local loopback Ollama endpoint.
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 18 — AnythingLLM installed with local-Ollama defaults"

APP_PATH="/opt/aiobi/AnythingLLMDesktop.AppImage"
assert_executable "$APP_PATH"

# Menu entry
DESKTOP=/usr/share/applications/aiobi-anythingllm.desktop
assert_file "$DESKTOP"
if [ -f "$DESKTOP" ]; then
    assert_grep "$DESKTOP" "Exec=$APP_PATH"
fi

# Skel default preferences: presence is required, and it must point at the
# local loopback endpoint so a freshly-created user is wired to the local
# Ollama daemon out of the box.
SKEL_CFG=/etc/skel/.config/anythingllm-desktop/preferences.json
assert_file "$SKEL_CFG"
if [ -f "$SKEL_CFG" ]; then
    assert_grep "$SKEL_CFG" "127.0.0.1:11434"
    assert_grep "$SKEL_CFG" "ollama"
fi

finalize
