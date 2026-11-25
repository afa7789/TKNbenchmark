#!/usr/bin/env bash
# Build an optimized release binary and place it at ./app.
set -euo pipefail
cd "$(dirname "$0")"
cabal build -v1 --offline -O2 exe:lru
cp "$(cabal list-bin --offline -O2 exe:lru)" ./app.tmp
mv -f ./app.tmp ./app
