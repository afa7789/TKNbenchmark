#!/usr/bin/env bash
# Builds an optimized release binary of wordfreq at ./app.
set -euo pipefail
cd "$(dirname "$0")"

zig build-exe src/main.zig \
  -O ReleaseFast \
  --name app \
  -femit-bin=app \
  --cache-dir .zig-cache \
  --global-cache-dir .zig-cache/global
