#!/usr/bin/env bash
# Builds an optimized release binary at ./app. Uses only the Nim stdlib.
set -euo pipefail
cd "$(dirname "$0")"
nim c -d:release --opt:speed --mm:orc --hints:off --nimcache:.nimcache -o:app src/app.nim
