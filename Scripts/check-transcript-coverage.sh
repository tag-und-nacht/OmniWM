#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Phase 05 (VWS-14) gate. Asserts that every Phase 05 transcript named
# in the rewrite plan has a corresponding golden test file under
# `Tests/OmniWMTests/Transcripts/Goldens/` and that the
# `RELIABILITY-MIGRATION.md` Phase 05 table mentions each transcript by
# slice ID.
#
# This is the structural counterpart to `check-direct-mutation-callers.sh`
# — it polices a process invariant rather than a code invariant.
# Hooked into `make verify`.

set -euo pipefail

cd "$(dirname "$0")/.."

GOLDENS_DIR="Tests/OmniWMTests/Transcripts/Goldens"
MIGRATION_DOC="docs/RELIABILITY-MIGRATION.md"

# Map slice ID → expected golden file name. The list is intentionally
# explicit so a future transcript addition has to update this script
# (which then exercises both halves of the gate).
declare -a EXPECTED_TRANSCRIPTS=(
    "VWS-04|NativeFullscreenReplacementRestoreTranscript.swift"
    "VWS-05|NiriFocusedRemovalTranscript.swift"
    "VWS-06|MonitorRebindReconnectTranscript.swift"
    "VWS-07|FailedFrameWriteRecoveryTranscript.swift"
    "VWS-08|IPCSubscribeRaceTranscript.swift"
    "VWS-09|IPCAuthorizationBoundaryTranscript.swift"
    "VWS-10|FloatingChildStackingTranscript.swift"
    "VWS-11|DwindleGestureTranscript.swift"
)

errors=0

if [[ ! -d "$GOLDENS_DIR" ]]; then
    echo "ERROR: missing transcripts goldens directory: $GOLDENS_DIR"
    exit 1
fi

for entry in "${EXPECTED_TRANSCRIPTS[@]}"; do
    slice_id="${entry%%|*}"
    file_name="${entry##*|}"
    full_path="$GOLDENS_DIR/$file_name"

    if [[ ! -f "$full_path" ]]; then
        echo "ERROR: $slice_id missing golden file at $full_path"
        errors=$((errors + 1))
        continue
    fi

    # Test file name = transcript file name with `Transcript.swift` →
    # `Tests.swift`.
    test_file="${full_path%Transcript.swift}Tests.swift"
    if [[ ! -f "$test_file" ]]; then
        echo "ERROR: $slice_id missing test file at $test_file"
        errors=$((errors + 1))
    fi

    if ! grep -q "$slice_id" "$MIGRATION_DOC" 2>/dev/null; then
        echo "ERROR: $slice_id missing from $MIGRATION_DOC"
        errors=$((errors + 1))
    fi
done

if [[ $errors -gt 0 ]]; then
    echo
    echo "Transcript coverage check failed with $errors error(s)."
    echo "If you intentionally removed a transcript, update Scripts/check-transcript-coverage.sh."
    echo "If you added a new lifecycle/focus/topology fix, add or update a transcript under $GOLDENS_DIR."
    exit 1
fi

echo "Transcript coverage OK (${#EXPECTED_TRANSCRIPTS[@]} transcripts pinned)."
