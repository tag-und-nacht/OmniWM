#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu

CONFIG=${1:-debug}
ARCHS=${2:-${OMNIWM_ZIG_KERNEL_ARCHS:-universal}}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ZIG_ROOT="$ROOT_DIR/Zig/omniwm_kernels"
OUTPUT_ROOT=${OMNIWM_ZIG_KERNEL_OUTPUT_ROOT:-"$ROOT_DIR/.build/zig-kernels"}

if [ "$CONFIG" = "all" ]; then
  "$SCRIPT_DIR/build-zig-kernels.sh" debug "$ARCHS"
  "$SCRIPT_DIR/build-zig-kernels.sh" release "$ARCHS"
  exit 0
fi

case "$ARCHS" in
  universal|arm64|x86_64)
    ;;
  *)
    echo "error: unsupported architecture set: $ARCHS (use universal, arm64, or x86_64)" >&2
    exit 1
    ;;
esac

OUTPUT_DIR="$OUTPUT_ROOT/$CONFIG"
ARM64_DIR="$OUTPUT_DIR/arm64"
X86_64_DIR="$OUTPUT_DIR/x86_64"
LIB_DIR="$OUTPUT_DIR/lib"
UNIVERSAL_LIB="$LIB_DIR/libomniwm_kernels.a"
CACHE_ROOT="$OUTPUT_ROOT/cache"
ARM64_CACHE_DIR="$CACHE_ROOT/$CONFIG-arm64-local"
X86_64_CACHE_DIR="$CACHE_ROOT/$CONFIG-x86_64-local"
GLOBAL_CACHE_DIR="$CACHE_ROOT/global"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/build-common.sh"
omniwm_load_build_metadata "$ROOT_DIR"
omniwm_require_zig_build_config "$CONFIG"
omniwm_require_zig_version
if [ "$ARCHS" = "universal" ]; then
  omniwm_require_command lipo
fi
omniwm_require_command ranlib
omniwm_require_file "$ZIG_ROOT/build.zig"
omniwm_require_file "$ZIG_ROOT/src/root.zig"

OPTIMIZE=$(omniwm_zig_optimize_for_config "$CONFIG")
ARM64_TARGET=$(omniwm_zig_target_for_arch arm64)
X86_64_TARGET=$(omniwm_zig_target_for_arch x86_64)

rm -rf "$LIB_DIR"
mkdir -p "$LIB_DIR" "$GLOBAL_CACHE_DIR"

if [ "$ARCHS" = "universal" ] || [ "$ARCHS" = "arm64" ]; then
  rm -rf "$ARM64_DIR" "$ARM64_CACHE_DIR"
  mkdir -p "$ARM64_CACHE_DIR"

  echo "Building OmniWM Zig kernels (arm64, $OPTIMIZE) with Zig $OMNIWM_ACTUAL_ZIG_VERSION..."
  (
    cd "$ZIG_ROOT"
    zig build \
      --summary none \
      --prefix "$ARM64_DIR" \
      --cache-dir "$ARM64_CACHE_DIR" \
      --global-cache-dir "$GLOBAL_CACHE_DIR" \
      -Dtarget="$ARM64_TARGET" \
      -Doptimize="$OPTIMIZE"
  )
fi

if [ "$ARCHS" = "universal" ] || [ "$ARCHS" = "x86_64" ]; then
  rm -rf "$X86_64_DIR" "$X86_64_CACHE_DIR"
  mkdir -p "$X86_64_CACHE_DIR"

  echo "Building OmniWM Zig kernels (x86_64, $OPTIMIZE) with Zig $OMNIWM_ACTUAL_ZIG_VERSION..."
  (
    cd "$ZIG_ROOT"
    zig build \
      --summary none \
      --prefix "$X86_64_DIR" \
      --cache-dir "$X86_64_CACHE_DIR" \
      --global-cache-dir "$GLOBAL_CACHE_DIR" \
      -Dtarget="$X86_64_TARGET" \
      -Doptimize="$OPTIMIZE"
  )
fi

case "$ARCHS" in
  universal)
    echo "Creating universal OmniWM Zig kernel archive..."
    lipo -create \
      "$ARM64_DIR/lib/libomniwm_kernels.a" \
      "$X86_64_DIR/lib/libomniwm_kernels.a" \
      -output "$UNIVERSAL_LIB"
    ;;
  arm64)
    cp "$ARM64_DIR/lib/libomniwm_kernels.a" "$UNIVERSAL_LIB"
    ;;
  x86_64)
    cp "$X86_64_DIR/lib/libomniwm_kernels.a" "$UNIVERSAL_LIB"
    ;;
esac

ranlib "$UNIVERSAL_LIB"

echo "Built $UNIVERSAL_LIB"
