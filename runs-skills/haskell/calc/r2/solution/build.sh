#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
ghc -XGHC2024 -O2 -Wall -Wcompat -outputdir build -o build/app src/Main.hs
cp -f build/app ./app
