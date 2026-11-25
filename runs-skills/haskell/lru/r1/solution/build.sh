#!/usr/bin/env bash
# Build an optimized release binary and place it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

builddir=dist-newstyle
cabal build --builddir="$builddir" -O2 exe:lru
cp "$(cabal list-bin --builddir="$builddir" -O2 exe:lru)" ./app
strip ./app 2>/dev/null || true
