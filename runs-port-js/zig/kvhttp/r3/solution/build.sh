#!/usr/bin/env bash
# Builds an optimized release binary of the server and places it at ./app.
# Requires Zig 0.16.0; there are no third-party dependencies to fetch.
set -euo pipefail
cd "$(dirname "$0")"

command -v zig >/dev/null || { echo "build.sh: zig 0.16.0 is required" >&2; exit 1; }

zig build -Doptimize=ReleaseFast --prefix zig-out
install -m 0755 zig-out/bin/kvhttp app
