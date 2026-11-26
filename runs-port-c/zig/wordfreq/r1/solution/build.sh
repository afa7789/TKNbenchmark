#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$PWD/.zig-cache/global}"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$PWD/.zig-cache/local}"
zig build-exe src/main.zig -O ReleaseFast -fstrip -femit-bin=app --name app
