#!/usr/bin/env bash
# Builds an optimized release binary of calc and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

zig build-exe src/main.zig \
    -O ReleaseFast \
    -fstrip \
    -fsingle-threaded \
    --name app \
    --cache-dir .zig-cache \
    --global-cache-dir .zig-cache/global

rm -f app.o
