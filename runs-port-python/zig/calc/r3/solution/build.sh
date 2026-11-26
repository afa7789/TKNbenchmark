#!/usr/bin/env bash
# Build an optimized release binary of calc and install it as ./app.
set -euo pipefail
cd "$(dirname "$0")"

zig build -Doptimize=ReleaseFast --prefix zig-out
cp zig-out/bin/calc app
chmod +x app
