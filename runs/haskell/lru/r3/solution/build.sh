#!/usr/bin/env bash
# Build an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
ghc -O2 -rtsopts "-with-rtsopts=-A64m" \
  -isrc -outputdir build \
  -package bytestring -package array \
  -o app src/Main.hs
