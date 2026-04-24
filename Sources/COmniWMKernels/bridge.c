// SPDX-License-Identifier: GPL-2.0-only
#include "omniwm_kernels.h"

// ABI-07 (Phase 06): include the generated parity header so any size /
// alignment drift in `omniwm_kernels.h` fails the kernel target's C
// compile. The generator regenerates this header from the schema; the
// drift check (`make check-kernel-abi-goldens`) re-emits and diffs.
#include "omniwm_kernels_generated.h"
