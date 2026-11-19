#!/usr/bin/env bash
# Shared paths for the Nimbus Remote build scripts. Sourced, not run.
# SRC  = the repository (this folder's parent)
# DIST = where deploy.sh puts the self-contained app (default: next to the repository)
NIMBUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$NIMBUS_DIR/.." && pwd)"
DIST="${DIST:-$(cd "$SRC/.." && pwd)/dist}"
