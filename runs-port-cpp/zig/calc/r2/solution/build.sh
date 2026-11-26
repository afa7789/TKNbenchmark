#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-cache/global"
zig build -Doptimize=ReleaseFast --prefix zig-out
cp zig-out/bin/app ./app
