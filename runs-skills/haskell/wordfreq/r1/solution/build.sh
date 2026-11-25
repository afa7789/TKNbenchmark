#!/usr/bin/env bash
# Build an optimized release binary and place it at ./app.
set -euo pipefail
cd "$(dirname "$0")"
cabal build -v1 exe:wordfreq
install -m 755 "$(cabal list-bin exe:wordfreq)" ./app.tmp
mv -f ./app.tmp ./app
