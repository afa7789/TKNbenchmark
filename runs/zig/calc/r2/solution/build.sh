#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
zig build -Doptimize=ReleaseFast
cp zig-out/bin/app ./app
