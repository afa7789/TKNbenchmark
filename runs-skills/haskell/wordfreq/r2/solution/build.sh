#!/usr/bin/env bash
# Build an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
cabal build -v0 exe:wordfreq
install -m 755 "$(cabal list-bin exe:wordfreq)" ./app.tmp
mv -f ./app.tmp ./app
