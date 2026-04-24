#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# ABI-07 (Phase 06): drift check for the generated kernel ABI goldens
# fixture (`Tests/OmniWMTests/KernelABIGoldens.swift`).
#
# Wraps `swift test --filter "KernelABISchemaGeneratorTests"` so the check
# can run inside `make verify` with a clear pass/fail. The test itself does
# the comparison against `KernelABISchema.currentLayouts()` and reports a
# per-typedef diff on failure. Regeneration is a separate target
# (`make regen-kernel-abi-goldens`) that re-runs the same test with
# `OMNIWM_REGENERATE_KERNEL_ABI_GOLDENS=1`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

LIBRARY_PATH="$(./Scripts/build-preflight.sh print-ghostty-library-dir)${LIBRARY_PATH:+:$LIBRARY_PATH}" \
    swift test --filter "KernelABISchemaGeneratorTests" >/tmp/check-kernel-abi-goldens.log 2>&1 || {
    echo "check-kernel-abi-goldens: FAIL" >&2
    echo "" >&2
    cat /tmp/check-kernel-abi-goldens.log >&2
    echo "" >&2
    echo "Run \`make regen-kernel-abi-goldens\` to update the goldens fixture." >&2
    exit 1
}

echo "check-kernel-abi-goldens: PASS"
