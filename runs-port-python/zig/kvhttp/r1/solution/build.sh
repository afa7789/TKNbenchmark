#!/usr/bin/env bash
# Build an optimized kvhttp binary and place it at ./app.
# Uses only the Zig standard library, so there is nothing to fetch.
set -euo pipefail
cd "$(dirname "$0")"

zig build -Doptimize=ReleaseFast --prefix zig-out
cp zig-out/bin/kvhttp app
