#!/usr/bin/env bash
# Builds and runs the instant replay end-to-end test. Run from MSYS2 MINGW64.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
OUT="$SRC/build/test-replay.exe"
mkdir -p "$SRC/build"
g++ -std=c++17 -O2 -fPIC \
  -I"$SRC/gui/include" \
  "$NIMBUS_DIR/test-replay.cpp" "$SRC/gui/src/recorder.cpp" "$SRC/gui/src/replaybuffer.cpp" \
  $(pkg-config --cflags --libs Qt6Core libavformat libavcodec libavutil) \
  -o "$OUT"
"$OUT"
