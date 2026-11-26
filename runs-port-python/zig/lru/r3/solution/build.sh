#!/usr/bin/env bash
# Build an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
zig build-exe src/main.zig -O ReleaseFast -fstrip -fsingle-threaded --name app --cache-dir .zig-cache --global-cache-dir .zig-cache/global
rm -f app.o
