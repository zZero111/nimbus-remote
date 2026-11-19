#!/usr/bin/env bash
# Configures and builds the app. Run from MSYS2 MINGW64, from the real path (not a junction:
# the curl patch step's `git apply` refuses paths that go through one).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$SRC"
[ -f build/build.ninja ] || cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCHIAKI_ENABLE_CLI=OFF
cmake --build build --target chiaki
echo "built: $SRC/build/gui/chiaki.exe"
