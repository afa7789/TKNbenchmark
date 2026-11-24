#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
nim c -d:release --opt:speed --hints:off --nimcache:.nimcache -o:app src/kvhttp.nim
