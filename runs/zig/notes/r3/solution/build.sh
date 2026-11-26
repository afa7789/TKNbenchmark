#!/usr/bin/env bash
# Builds the optimized release binary and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"
zig build -Doptimize=ReleaseSafe --prefix zig-out
cp zig-out/bin/notes ./app
