#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
zig build-exe src/main.zig -O ReleaseFast -fstrip -femit-bin=app
rm -f app.o
