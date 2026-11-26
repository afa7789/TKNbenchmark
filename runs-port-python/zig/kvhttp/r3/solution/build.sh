#!/usr/bin/env bash
# Builds an optimized release binary of the kvhttp server at ./app.
# Requires Zig 0.16.0. No third-party dependencies.
set -euo pipefail
cd "$(dirname "$0")"

zig build -Doptimize=ReleaseFast --prefix zig-out
cp zig-out/bin/kvhttp app
