#!/usr/bin/env bash
# Builds an optimised release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
ghc -O2 -Wall -isrc -outputdir build -o app exe/Main.hs
