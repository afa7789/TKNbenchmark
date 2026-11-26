#!/usr/bin/env bash
# Builds the optimized release binary at ./app.
# Dependencies (SQLite) are declared in build.zig.zon and fetched by zig.
set -euo pipefail
cd "$(dirname "$0")"

zig build --fetch
zig build -Doptimize=ReleaseSafe --prefix zig-out
install -m 0755 zig-out/bin/notes app
