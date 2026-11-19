#!/usr/bin/env bash
# Builds and runs the AsyncVideoDecoder test. Run from MSYS2 MINGW64.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
OUT="$SRC/build/test-asyncdecoder.exe"
mkdir -p "$SRC/build"
g++ -std=c++17 -O2 -pthread \
  -I"$SRC/gui/include" \
  "$NIMBUS_DIR/test-asyncdecoder.cpp" "$SRC/gui/src/asyncdecoder.cpp" \
  -o "$OUT"
"$OUT"
