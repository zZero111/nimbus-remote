#!/usr/bin/env bash
# Builds the non-pacman dependencies into /mingw64 (mirrors .github/workflows/build-msys2.yml).
# Run from an MSYS2 MINGW64 shell. Safe to re-run: finished steps are skipped.
# chiaki-ng's dependency scripts break on spaces in the path: if the repository path has one,
# run this through a junction without spaces (see NIMBUS.md).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
WORK="$SRC/build-deps"
mkdir -p "$WORK"

if ! pkg-config --exists libplacebo; then
  echo "== libplacebo"
  bash "$SRC/scripts/build-libplacebo-windows.sh" build-deps
fi

if [ ! -f /mingw64/include/libavcodec/avcodec.h ] || ! ls /mingw64/bin/avcodec-*.dll >/dev/null 2>&1; then
  echo "== ffmpeg (upstream chiaki-ng build)"
  cd "$WORK"
  Z=ffmpeg-n9.0-latest-win64-gpl-shared-9.0
  [ -f "$Z.zip" ] || curl -fL -o "$Z.zip" "https://github.com/streetpea/FFmpeg-Builds/releases/download/latest/$Z.zip"
  rm -rf "$Z"; unzip -q "$Z.zip"
  cp -a "$Z/bin/." /mingw64/bin
  cp -a "$Z/include/." /mingw64/include
  cp -a "$Z/lib/." /mingw64/lib
fi

if [ ! -f /mingw64/lib/pkgconfig/sdl2.pc ] || ! grep -q compat /mingw64/lib/pkgconfig/sdl2.pc; then
  echo "== SDL3 + sdl2-compat"
  INSTALL_PREFIX=/mingw64 bash "$SRC/scripts/build-sdl2-compat.sh" build-deps
  cp /mingw64/lib/pkgconfig/sdl2-compat.pc /mingw64/lib/pkgconfig/sdl2.pc
fi

if [ ! -f /mingw64/include/hidapi/hidapi.h ]; then
  echo "== hidapi"
  INSTALL_PREFIX=/mingw64 bash "$SRC/scripts/build-hidapi.sh" build-deps
fi
echo "deps ready"
