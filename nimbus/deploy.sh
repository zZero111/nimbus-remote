#!/usr/bin/env bash
# Bundles build/gui/chiaki.exe with its DLLs, Qt plugins and QML into $DIST. Run from MSYS2 MINGW64.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$SRC"
rm -rf "$DIST"
bash scripts/deploy-windows-msys2.sh "$DIST" build/gui/chiaki.exe \
  "$SRC/build/third-party/cpp-steam-tools" /mingw64 gui/src/qml
echo "deployed to $DIST"
