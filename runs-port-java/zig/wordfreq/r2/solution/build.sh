#!/usr/bin/env bash
# Builds an optimized release binary and installs it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

export ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-cache/global"
zig build -Doptimize=ReleaseFast --prefix zig-out
install -m 755 zig-out/bin/app app
