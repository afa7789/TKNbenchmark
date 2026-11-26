#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
zig build -Doptimize=ReleaseFast --cache-dir .zig-cache --global-cache-dir .zig-cache/global --prefix zig-out
cp zig-out/bin/app ./app
