#!/usr/bin/env bash
# =============================================================================
# Test — Step 15 — Ollama daemon + pre-pulled models
# =============================================================================
# Verifies that Ollama is installed to /usr/local/bin/ollama, that the
# loopback + keep-alive drop-in is in place, that the first-boot pull
# service is registered, that the service body references the two Aïobi
# model tags (and NOT the base qwen3-vl:2b tag or the deprecated
# qwen2.5-coder:0.5b tag), and that the /usr/share/ollama directory is
# owned by the ollama user.
# =============================================================================

set -euo pipefail
. "$(dirname "$0")/_common.sh"

TEST_TITLE="Step 15 — Ollama loopback-bound with pre-pull unit and correct model tags"

# 1. Binary at the upstream install location.
if [ -x /usr/local/bin/ollama ]; then
    pass "ollama binary at /usr/local/bin/ollama"
else
    fail "ollama binary at /usr/local/bin/ollama" "missing or not executable"
fi

# 2. Drop-in with loopback bind + keep-alive.
DROPIN=/etc/systemd/system/ollama.service.d/override.conf
assert_file "$DROPIN"
if [ -f "$DROPIN" ]; then
    # After step 19 the bind is on 11435 (private) with the socket proxy on
    # 11434. Before step 19, or on an installation that skips it, the direct
    # bind is on 11434. Both are acceptable.
    if grep -qE 'OLLAMA_HOST=127\.0\.0\.1:(11434|11435)' "$DROPIN"; then
        pass "drop-in sets OLLAMA_HOST to 127.0.0.1:11434 or 11435"
    else
        fail "drop-in sets OLLAMA_HOST to 127.0.0.1:11434 or 11435" "no matching Environment line"
    fi
    assert_grep "$DROPIN" "OLLAMA_KEEP_ALIVE=5m"
fi

# 3. First-boot pull unit.
FIRSTPULL=/etc/systemd/system/aiobi-ollama-firstpull.service
assert_systemd_unit "$FIRSTPULL"

# 4. Model tag discipline. The expected tags are the exact strings below;
# the deprecated tags must NOT appear.
if [ -f "$FIRSTPULL" ]; then
    assert_grep "$FIRSTPULL" "qwen2.5:1.5b"
    assert_grep "$FIRSTPULL" "qwen3-vl:2b-instruct-q8_0"

    # Base qwen3-vl:2b tag (without the instruct suffix) must be absent.
    # The strict check is "qwen3-vl:2b followed by anything other than -".
    if grep -qE 'qwen3-vl:2b($|[^-])' "$FIRSTPULL"; then
        fail "unit does not reference base tag qwen3-vl:2b" "found base tag without instruct suffix"
    else
        pass "unit does not reference base tag qwen3-vl:2b"
    fi

    # Deprecated coder tag must be absent.
    assert_no_grep "$FIRSTPULL" "qwen2.5-coder:0.5b"
fi

# 5. /usr/share/ollama ownership must be ollama:ollama (chown -R effect).
if [ -d /usr/share/ollama ]; then
    owner=$(stat -c '%U:%G' /usr/share/ollama 2>/dev/null || echo "?")
    if [ "$owner" = "ollama:ollama" ]; then
        pass "/usr/share/ollama owned by ollama:ollama"
    else
        fail "/usr/share/ollama owned by ollama:ollama" "actual owner: $owner"
    fi
else
    skip "/usr/share/ollama ownership" "directory absent (daemon never started)"
fi

# 6. Models baked into the ISO (air-gapped install support). The chroot-time
# pull in script 15 must have populated blobs for both Qwen models; on the
# installed VM the same files are expected. Both manifests + at least one
# blob per model must be present. If the blobs dir is empty or absent, the
# pull did not complete and the air-gapped positioning is broken.
MODELS_DIR=/usr/share/ollama/.ollama/models
BLOBS_DIR="$MODELS_DIR/blobs"
if [ -d "$BLOBS_DIR" ]; then
    blob_count=$(find "$BLOBS_DIR" -maxdepth 1 -type f -name 'sha256-*' 2>/dev/null | wc -l)
    if [ "$blob_count" -ge 6 ]; then
        # Two Qwen models typically pull 4-6 blobs each (config + weights +
        # tokenizer + template) — 6 total is the safe floor.
        pass "$BLOBS_DIR has $blob_count blob file(s) (models baked in)"
    else
        fail "$BLOBS_DIR has enough blobs" "only $blob_count blob(s) — models not fully pulled"
    fi

    # Assert both model manifests are present so a partial pull is caught.
    if [ -d "$MODELS_DIR/manifests/registry.ollama.ai/library/qwen2.5" ]; then
        pass "manifest present: qwen2.5"
    else
        fail "manifest present: qwen2.5" "manifests/registry.ollama.ai/library/qwen2.5/ missing"
    fi
    if [ -d "$MODELS_DIR/manifests/registry.ollama.ai/library/qwen3-vl" ]; then
        pass "manifest present: qwen3-vl"
    else
        fail "manifest present: qwen3-vl" "manifests/registry.ollama.ai/library/qwen3-vl/ missing"
    fi
else
    fail "$BLOBS_DIR present" "blobs directory missing — models not pulled at chroot or first boot"
fi

finalize
