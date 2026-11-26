#!/usr/bin/env bash
# Builds an optimized release binary of kvhttp and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

command -v zig >/dev/null || { echo "zig 0.16 is required" >&2; exit 1; }

zig build -Doptimize=ReleaseFast --prefix zig-out
# Replace ./app rather than overwriting it in place: macOS kills processes
# whose executable was modified after its code signature was cached.
rm -f app
cp zig-out/bin/kvhttp app
