#!/usr/bin/env bash
# Builds an optimized release binary and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cabal update
cabal build exe:kvhttp --enable-optimization=2
install -m 0755 "$(cabal list-bin exe:kvhttp --enable-optimization=2)" ./app.tmp
mv -f ./app.tmp ./app
