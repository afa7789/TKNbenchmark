#!/usr/bin/env bash
# Builds an optimized release binary of the server and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"
command -v zig >/dev/null || { echo "zig (0.16.0) is required" >&2; exit 1; }
zig build -Doptimize=ReleaseFast --prefix zig-out
cp zig-out/bin/kvhttp app
