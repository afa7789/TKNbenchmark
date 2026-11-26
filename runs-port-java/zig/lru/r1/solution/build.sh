#!/usr/bin/env bash
# Builds an optimized release binary of the LRU cache simulator at ./app.
set -euo pipefail
cd "$(dirname "$0")"

zig build-exe src/main.zig -O ReleaseFast -fstrip -femit-bin=app --cache-dir .zig-cache --global-cache-dir .zig-cache/global
rm -f app.o
