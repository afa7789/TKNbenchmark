#!/usr/bin/env bash
# Builds an optimized release binary of the LRU simulator at ./app.
set -euo pipefail
cd "$(dirname "$0")"

# Keep all build artefacts inside this directory.
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"
export ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-cache/global"

zig build -Doptimize=ReleaseFast --prefix zig-out
cp zig-out/bin/lru app
chmod +x app
