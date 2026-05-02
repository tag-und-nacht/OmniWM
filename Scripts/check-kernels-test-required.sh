#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# ABI-10 (Phase 06): bridge-changed gate.
#
# Fails when the Swift/Zig bridge surface has been modified more recently
# than the last successful `make kernels-test` run. The marker is a
# timestamp file at `.build/.kernels-test-passed` that the `kernels-test`
# Makefile target updates on success.
#
# Tracked bridge surface:
#   - `Sources/COmniWMKernels/**`
#   - `Zig/omniwm_kernels/**`
#   - `Tests/OmniWMTests/*KernelABITests.swift`
#   - `Tests/OmniWMTests/KernelABILayoutGoldenTests.swift`
#   - `Tests/OmniWMTests/KernelABIInvalidInputTests.swift`
#   - `Tests/OmniWMTests/KernelABIBufferSizeTests.swift`
#   - `Tests/OmniWMTests/KernelABIOwnershipContractTests.swift`
#   - `Tests/OmniWMTests/KernelABIPerKernelOwnershipTests.swift`
#   - `Tests/OmniWMTests/KernelABIIPCSocketTests.swift`
#   - `Tests/OmniWMTests/KernelABIStringHelperOwnershipTests.swift`
#   - `Tests/OmniWMTests/WorkspaceSessionKernelBridgeTests.swift`
#   - `Tests/OmniWMTests/WorkspaceSessionLogicalIdentityTests.swift`
#
# Hooked into `make verify` after `check-direct-mutation-callers` and
# `check-transcript-coverage`. The check is advisory in spirit (prompts the
# user to run `make kernels-test`) and enforced by exit code (fails the
# verify pipeline so accidental drift cannot ship as "verified").
#
# Allowlist override: set `OMNIWM_SKIP_KERNELS_TEST_CHECK=1` to bypass for
# bisects or rebases that touch bridge files for unrelated reasons. The
# bypass is logged so it is observable in CI / hand-off summaries.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

MARKER=".build/.kernels-test-passed"

if [[ "${OMNIWM_SKIP_KERNELS_TEST_CHECK:-0}" == "1" ]]; then
    echo "check-kernels-test-required: bypass requested via OMNIWM_SKIP_KERNELS_TEST_CHECK=1"
    exit 0
fi

# Files that, when changed, require `make kernels-test` to have been run.
# Globs are expanded via `find` to keep the script free of bash 4 globstar
# requirements (macOS ships bash 3.2 by default).
read -r -d '' BRIDGE_PATHS <<'PATHS' || true
Sources/COmniWMKernels
Zig/omniwm_kernels
Tests/OmniWMTests/NiriLayoutKernelABITests.swift
Tests/OmniWMTests/OrchestrationKernelABITests.swift
Tests/OmniWMTests/OverviewProjectionKernelABITests.swift
Tests/OmniWMTests/ReconcileKernelABITests.swift
Tests/OmniWMTests/RestorePlannerKernelABITests.swift
Tests/OmniWMTests/WindowDecisionKernelABITests.swift
Tests/OmniWMTests/WorkspaceNavigationKernelABITests.swift
Tests/OmniWMTests/WorkspaceSessionKernelABITests.swift
Tests/OmniWMTests/WorkspaceSessionKernelBridgeTests.swift
Tests/OmniWMTests/WorkspaceSessionLogicalIdentityTests.swift
Tests/OmniWMTests/KernelABILayoutGoldenTests.swift
Tests/OmniWMTests/KernelABIInvalidInputTests.swift
Tests/OmniWMTests/KernelABIBufferSizeTests.swift
Tests/OmniWMTests/KernelABIOwnershipContractTests.swift
Tests/OmniWMTests/KernelABIPerKernelOwnershipTests.swift
Tests/OmniWMTests/KernelABIIPCSocketTests.swift
Tests/OmniWMTests/KernelABIStringHelperOwnershipTests.swift
PATHS

if [[ ! -e "$MARKER" ]]; then
    # Find any tracked bridge file. If none exist, the workspace is clean
    # and the marker absence is irrelevant; if any exist, the user needs to
    # run `make kernels-test` to create the marker.
    HAVE_BRIDGE_FILES=0
    while IFS= read -r path; do
        if [[ -e "$path" ]]; then
            HAVE_BRIDGE_FILES=1
            break
        fi
    done <<< "$BRIDGE_PATHS"

    if [[ "$HAVE_BRIDGE_FILES" == "1" ]]; then
        cat >&2 <<'MSG'
check-kernels-test-required: FAIL

The Swift/Zig bridge surface exists but `make kernels-test` has never been
run successfully on this checkout (`.build/.kernels-test-passed` marker is
absent).

Run:

    make kernels-test

before declaring `make verify` complete. The marker is updated on success
and tracked-but-untouched bridge files won't trip this check on future
runs.

To bypass for a specific run (e.g., bisect, rebase):

    OMNIWM_SKIP_KERNELS_TEST_CHECK=1 make verify
MSG
        exit 1
    fi
    exit 0
fi

# Marker exists. Find any bridge file modified more recently.
NEWER_FILES=$(find $BRIDGE_PATHS -type f -newer "$MARKER" 2>/dev/null | head -20 || true)

if [[ -z "$NEWER_FILES" ]]; then
    exit 0
fi

cat >&2 <<MSG
check-kernels-test-required: FAIL

The Swift/Zig bridge surface has been modified since the last successful
\`make kernels-test\` run. Files newer than the
\`.build/.kernels-test-passed\` marker:

$NEWER_FILES

Run:

    make kernels-test

before declaring \`make verify\` complete. The marker is updated on
success.

To bypass for a specific run (e.g., bisect, rebase):

    OMNIWM_SKIP_KERNELS_TEST_CHECK=1 make verify
MSG
exit 1
