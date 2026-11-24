#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

CC="${CC:-cc}"
CFLAGS="-std=c17 -O2 -DNDEBUG -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wno-sign-conversion -pthread"

"$CC" $CFLAGS -o app src/main.c src/store.c
