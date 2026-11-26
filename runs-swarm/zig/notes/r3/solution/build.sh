#!/usr/bin/env bash
# Builds the optimized release binary at ./app.
# Dependencies declared in build.zig.zon are fetched by `zig build` when missing.
set -euo pipefail
cd "$(dirname "$0")"

zig build -Doptimize=ReleaseFast
install -m 0755 zig-out/bin/notes ./app
