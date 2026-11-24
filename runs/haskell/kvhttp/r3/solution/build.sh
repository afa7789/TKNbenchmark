#!/usr/bin/env bash
# Builds an optimized release binary and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cabal update
cabal build exe:kvhttp
cp "$(cabal list-bin exe:kvhttp)" ./app.tmp
mv -f ./app.tmp ./app
