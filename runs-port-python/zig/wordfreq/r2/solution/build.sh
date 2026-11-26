#!/usr/bin/env bash
# Build an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
zig build-exe src/main.zig -OReleaseFast -fstrip -femit-bin=app \
    --cache-dir .zig-cache --global-cache-dir .zig-cache/global
rm -f app.o
