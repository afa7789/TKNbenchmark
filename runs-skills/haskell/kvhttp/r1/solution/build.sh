#!/usr/bin/env bash
# Build an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
cabal update
cabal build exe:app
cp "$(cabal list-bin exe:app)" ./app.tmp
mv -f ./app.tmp ./app
