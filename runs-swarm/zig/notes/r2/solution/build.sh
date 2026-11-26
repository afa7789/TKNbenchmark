#!/usr/bin/env bash
# Builds the optimized release binary at ./app. Dependencies declared in
# build.zig.zon (the SQLite amalgamation) are fetched by `zig build`.
set -euo pipefail
cd "$(dirname "$0")"

zig build --fetch
zig build -Doptimize=ReleaseFast --prefix zig-out
install -m 0755 zig-out/bin/app ./app
