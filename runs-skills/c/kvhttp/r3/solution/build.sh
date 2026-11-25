#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

CC="${CC:-cc}"
CFLAGS=(-std=c17 -O2 -DNDEBUG -Wall -Wextra -Wpedantic
        -fstack-protector-strong -D_FORTIFY_SOURCE=3 -ftrivial-auto-var-init=zero)

"$CC" "${CFLAGS[@]}" -pthread -o app src/main.c src/store.c
