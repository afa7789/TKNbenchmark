#!/usr/bin/env bash
# Builds an optimized release binary and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

zig build -Doptimize=ReleaseFast --prefix zig-out
cp zig-out/bin/wordfreq app
chmod +x app
