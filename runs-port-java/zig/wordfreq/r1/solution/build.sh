#!/usr/bin/env bash
# Builds an optimized wordfreq binary and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

export ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-cache/global"
zig build -Doptimize=ReleaseFast --prefix zig-out
cp zig-out/bin/app ./app
