#!/usr/bin/env bash
# Builds the optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
exec make -j"$jobs" all
