#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
zig build-exe src/main.zig -O ReleaseFast -femit-bin=app --name app
rm -f app.o
