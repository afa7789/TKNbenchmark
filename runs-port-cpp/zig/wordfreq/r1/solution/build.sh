#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
zig build-exe src/main.zig -O ReleaseFast -fstrip --name app --cache-dir .zig-cache --global-cache-dir "${ZIG_GLOBAL_CACHE_DIR:-.zig-cache/global}"
rm -f app.o
