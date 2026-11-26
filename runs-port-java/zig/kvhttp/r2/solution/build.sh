#!/usr/bin/env bash
# Builds an optimized kvhttp server and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

zig build -Doptimize=ReleaseFast --prefix zig-out
cp zig-out/bin/kvhttp app
