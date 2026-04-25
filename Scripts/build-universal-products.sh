#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT_DIR/Scripts/build-common.sh"
omniwm_load_build_metadata "$ROOT_DIR"

CONFIG="${1:-release}"
ARCHS="${2:-universal}"
omniwm_require_swiftpm_config "$CONFIG"
case "$ARCHS" in
  universal|arm64|x86_64)
    ;;
  *)
    echo "error: unsupported architecture set: $ARCHS (use universal, arm64, or x86_64)" >&2
    exit 1
    ;;
esac

CONFIG_CAPITALIZED="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"
ARM64_BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/$CONFIG"
X86_64_BUILD_DIR="$ROOT_DIR/.build/x86_64-apple-macosx/$CONFIG"
if [ "$ARCHS" = "universal" ]; then
  PRODUCT_BUILD_DIR="$ROOT_DIR/.build/apple/Products/$CONFIG_CAPITALIZED"
else
  PRODUCT_BUILD_DIR="$ROOT_DIR/.build/apple/Products/$CONFIG_CAPITALIZED-$ARCHS"
fi

omniwm_verify_ghostty_archive
omniwm_require_zig_version
omniwm_setup_ghostty_library_path
export OMNIWM_ZIG_KERNEL_ARCHS="$ARCHS"

echo "Using Zig $(zig version)"
echo "Using Ghostty archive digest $(omniwm_actual_ghostty_archive_sha256)"
if [ "$ARCHS" = "universal" ] || [ "$ARCHS" = "arm64" ]; then
  echo "Building OmniWM ($CONFIG) for arm64..."
  swift build -c "$CONFIG" --arch arm64
fi
if [ "$ARCHS" = "universal" ] || [ "$ARCHS" = "x86_64" ]; then
  echo "Building OmniWM ($CONFIG) for x86_64..."
  swift build -c "$CONFIG" --arch x86_64
fi

omniwm_require_command ditto
if [ "$ARCHS" = "universal" ]; then
  omniwm_require_command lipo
  omniwm_require_file "$ARM64_BUILD_DIR/OmniWM"
  omniwm_require_file "$X86_64_BUILD_DIR/OmniWM"
  omniwm_require_file "$ARM64_BUILD_DIR/omniwmctl"
  omniwm_require_file "$X86_64_BUILD_DIR/omniwmctl"
  omniwm_require_file "$ARM64_BUILD_DIR/OmniWM_OmniWM.bundle/kernels-built.txt"

  rm -rf "$PRODUCT_BUILD_DIR"
  mkdir -p "$PRODUCT_BUILD_DIR"

  echo "Assembling universal executables..."
  lipo -create -output "$PRODUCT_BUILD_DIR/OmniWM" \
    "$ARM64_BUILD_DIR/OmniWM" \
    "$X86_64_BUILD_DIR/OmniWM"
  lipo -create -output "$PRODUCT_BUILD_DIR/omniwmctl" \
    "$ARM64_BUILD_DIR/omniwmctl" \
    "$X86_64_BUILD_DIR/omniwmctl"
  ditto "$ARM64_BUILD_DIR/OmniWM_OmniWM.bundle" "$PRODUCT_BUILD_DIR/OmniWM_OmniWM.bundle"
else
  BUILD_DIR="$ROOT_DIR/.build/$ARCHS-apple-macosx/$CONFIG"
  omniwm_require_file "$BUILD_DIR/OmniWM"
  omniwm_require_file "$BUILD_DIR/omniwmctl"
  omniwm_require_file "$BUILD_DIR/OmniWM_OmniWM.bundle/kernels-built.txt"

  rm -rf "$PRODUCT_BUILD_DIR"
  mkdir -p "$PRODUCT_BUILD_DIR"

  echo "Assembling $ARCHS products..."
  ditto "$BUILD_DIR/OmniWM" "$PRODUCT_BUILD_DIR/OmniWM"
  ditto "$BUILD_DIR/omniwmctl" "$PRODUCT_BUILD_DIR/omniwmctl"
  ditto "$BUILD_DIR/OmniWM_OmniWM.bundle" "$PRODUCT_BUILD_DIR/OmniWM_OmniWM.bundle"
fi

echo "Products are available in $PRODUCT_BUILD_DIR"
