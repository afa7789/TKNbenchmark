#!/usr/bin/env bash
# Build an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p _build
ghc -XGHC2024 -O2 -Wall -Wcompat -outputdir _build -o app src/Main.hs
