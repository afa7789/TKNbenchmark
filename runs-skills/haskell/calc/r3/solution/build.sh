#!/usr/bin/env bash
# Build an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p _build
ghc -XGHC2024 -XLambdaCase -O2 -Wall -outputdir _build -o app.bin src/Main.hs
mv -f app.bin app
