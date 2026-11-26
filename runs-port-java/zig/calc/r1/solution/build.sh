#!/usr/bin/env bash
# Builds an optimized release binary of calc and installs it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

# Keep every build artifact inside this directory.
export ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-cache/global"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache/local"

zig build -Doptimize=ReleaseFast --prefix zig-out
install -m 755 zig-out/bin/calc app
