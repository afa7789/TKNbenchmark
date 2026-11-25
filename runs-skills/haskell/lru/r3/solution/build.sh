#!/usr/bin/env bash
# Build an optimized release binary and place it at ./app.
set -euo pipefail
cd "$(dirname "$0")"
cabal build -v1 -O2 exe:app
install -m 755 "$(cabal list-bin -O2 exe:app)" ./app
