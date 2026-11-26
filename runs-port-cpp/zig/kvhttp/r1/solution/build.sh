#!/usr/bin/env bash
# Builds an optimized release binary at ./app. No third-party dependencies.
set -euo pipefail
cd "$(dirname "$0")"

zig build -Doptimize=ReleaseSafe --prefix zig-out
cp zig-out/bin/kvhttp app
