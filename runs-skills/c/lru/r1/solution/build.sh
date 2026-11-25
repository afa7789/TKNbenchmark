#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
CC="${CC:-cc}"
"$CC" -std=c17 -O2 -DNDEBUG -Wall -Wextra -Wpedantic \
  -fstack-protector-strong -D_FORTIFY_SOURCE=3 \
  -o app src/main.c src/lru.c
