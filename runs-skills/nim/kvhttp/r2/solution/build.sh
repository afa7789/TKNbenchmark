#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
nim c -d:release --opt:speed --hints:off --out:app src/app.nim
