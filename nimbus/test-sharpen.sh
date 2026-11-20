#!/usr/bin/env bash
# Builds and runs the GPU sharpening/upscaling render test. Run from MSYS2 MINGW64.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
OUT="$SRC/build/test-sharpen.exe"
mkdir -p "$SRC/build"
gcc -std=c11 -O2 "$NIMBUS_DIR/test-sharpen.c" $(pkg-config --cflags --libs libplacebo) -lvulkan-1 -lm -o "$OUT"
"$OUT" "$SRC/gui/res/shaders"
