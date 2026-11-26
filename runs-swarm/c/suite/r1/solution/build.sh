#!/usr/bin/env bash
# Builds an optimized release binary at ./app from a clean tree.
set -euo pipefail
cd "$(dirname "$0")"

jobs=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
make clean >/dev/null
make -j"$jobs" OPTFLAGS="-O2 -DNDEBUG"
