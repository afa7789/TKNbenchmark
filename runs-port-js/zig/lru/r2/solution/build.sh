#!/usr/bin/env bash
# Builds an optimized release binary of the LRU simulator and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"
zig build-exe src/main.zig -O ReleaseFast -fstrip -femit-bin=app
rm -f app.o
