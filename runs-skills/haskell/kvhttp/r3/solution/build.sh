#!/usr/bin/env bash
# Build an optimized release binary of kvhttp and place it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cabal update
cabal build exe:kvhttp
cp "$(cabal list-bin exe:kvhttp)" ./app.tmp
mv -f ./app.tmp ./app
