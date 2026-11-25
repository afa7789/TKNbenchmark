#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
zig build-exe src/main.zig -O ReleaseFast --name app \
  --cache-dir .zig-cache --global-cache-dir .zig-cache/global
rm -f app.o
