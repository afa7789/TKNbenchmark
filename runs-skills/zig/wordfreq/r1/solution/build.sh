#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
zig build --release=fast --prefix-exe-dir . --prefix .
