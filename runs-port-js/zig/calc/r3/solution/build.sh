#!/usr/bin/env bash
# Builds an optimized release binary of the calculator and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"
zig build-exe src/main.zig -O ReleaseFast -fstrip --cache-dir .zig-cache --global-cache-dir .zig-cache/global -femit-bin=app
rm -f app.o
