#!/usr/bin/env bash
# Build an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
zig build -Doptimize=ReleaseFast --prefix zig-out
cp zig-out/bin/lru app
