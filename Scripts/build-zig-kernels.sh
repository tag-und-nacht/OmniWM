#!/bin/sh
set -eu

CONFIG=${1:-debug}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ZIG_ROOT="$ROOT_DIR/Zig/omniwm_kernels"
SOURCE_FILE="$ZIG_ROOT/src/root.zig"
OUTPUT_DIR="$ROOT_DIR/.build/zig-kernels"
ARM64_DIR="$OUTPUT_DIR/arm64"
X86_64_DIR="$OUTPUT_DIR/x86_64"
LIB_DIR="$OUTPUT_DIR/lib"
UNIVERSAL_LIB="$LIB_DIR/libomniwm_kernels.a"

case "$CONFIG" in
  debug)
    OPTIMIZE=Debug
    ;;
  release)
    OPTIMIZE=ReleaseFast
    ;;
  release-safe)
    OPTIMIZE=ReleaseSafe
    ;;
  release-small)
    OPTIMIZE=ReleaseSmall
    ;;
  *)
    echo "error: unsupported Zig kernel build configuration: $CONFIG" >&2
    echo "use one of: debug, release, release-safe, release-small" >&2
    exit 1
    ;;
esac

if ! command -v zig >/dev/null 2>&1; then
  echo "error: zig is required to build OmniWM kernels" >&2
  exit 1
fi

rm -rf "$ARM64_DIR" "$X86_64_DIR"
mkdir -p "$LIB_DIR"

echo "Building OmniWM Zig kernels (arm64, $OPTIMIZE)..."
mkdir -p "$ARM64_DIR/lib"
zig build-lib "$SOURCE_FILE" \
  -target aarch64-macos.15.0 \
  -O "$OPTIMIZE" \
  -lc \
  -femit-bin="$ARM64_DIR/lib/libomniwm_kernels.a"

echo "Building OmniWM Zig kernels (x86_64, $OPTIMIZE)..."
mkdir -p "$X86_64_DIR/lib"
zig build-lib "$SOURCE_FILE" \
  -target x86_64-macos.15.0 \
  -O "$OPTIMIZE" \
  -lc \
  -femit-bin="$X86_64_DIR/lib/libomniwm_kernels.a"

echo "Creating universal OmniWM Zig kernel archive..."
lipo -create \
  "$ARM64_DIR/lib/libomniwm_kernels.a" \
  "$X86_64_DIR/lib/libomniwm_kernels.a" \
  -output "$UNIVERSAL_LIB"

echo "Built $UNIVERSAL_LIB"
