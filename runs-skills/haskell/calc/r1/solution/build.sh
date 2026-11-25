#!/usr/bin/env bash
# Build an optimized release binary and place it at ./app.
set -euo pipefail
cd "$(dirname "$0")"
cabal build -v1 exe:calc
cp "$(cabal list-bin exe:calc)" ./app
