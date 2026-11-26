#!/usr/bin/env bash
# Builds an optimized release binary of kvhttp and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

command -v zig >/dev/null || { echo "zig 0.16 is required" >&2; exit 1; }

zig build -Doptimize=ReleaseFast --prefix zig-out
# Replace rather than overwrite: rewriting a signed Mach-O in place gets it
# killed by the kernel's code-signing cache on macOS.
rm -f app
cp zig-out/bin/kvhttp app
