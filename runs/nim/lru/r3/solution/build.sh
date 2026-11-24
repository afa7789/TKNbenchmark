#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
nim c -d:release --opt:speed --mm:orc --hints:off --nimcache:./.nimcache -o:./app src/lru.nim
