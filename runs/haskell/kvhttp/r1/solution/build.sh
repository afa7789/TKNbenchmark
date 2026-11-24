#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cabal update
cabal build exe:kvhttp --enable-optimization=2
rm -f ./app
cp "$(cabal list-bin exe:kvhttp --enable-optimization=2)" ./app
