#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

zig build -Doptimize=ReleaseFast --summary none
cp zig-out/bin/app ./app
