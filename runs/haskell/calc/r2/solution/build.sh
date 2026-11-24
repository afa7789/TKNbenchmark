#!/usr/bin/env bash
# Build an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
ghc -O2 -outputdir build -o app src/Main.hs
