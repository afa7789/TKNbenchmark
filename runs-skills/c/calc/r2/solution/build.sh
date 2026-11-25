#!/usr/bin/env bash
# Build the optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
CC="${CC:-cc}"
"$CC" -std=c17 -O2 -DNDEBUG -Wall -Wextra -Wpedantic \
    -fstack-protector-strong -D_FORTIFY_SOURCE=3 \
    -o app src/calc.c src/main.c
