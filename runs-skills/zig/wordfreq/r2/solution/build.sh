#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
zig build-exe src/main.zig -O ReleaseFast -fsingle-threaded --name app -femit-bin=app --cache-dir .zig-cache --global-cache-dir .zig-cache/global
