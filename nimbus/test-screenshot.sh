#!/usr/bin/env bash
# Builds and runs the screenshot colour-conversion test. Run from MSYS2 MINGW64.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
OUT="$SRC/build/test-screenshot.exe"
mkdir -p "$SRC/build"
g++ -std=c++17 -O2 -fPIC \
  -I"$SRC/gui/include" \
  "$NIMBUS_DIR/test-screenshot.cpp" "$SRC/gui/src/screenshot.cpp" \
  $(pkg-config --cflags --libs Qt6Gui Qt6Concurrent libavutil) \
  -o "$OUT"
"$OUT"
