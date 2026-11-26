#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf app zig-out
zig build -Doptimize=ReleaseFast --prefix zig-out
cp zig-out/bin/app app
