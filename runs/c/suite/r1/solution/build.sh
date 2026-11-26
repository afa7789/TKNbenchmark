#!/usr/bin/env bash
# Build an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
CC="${CC:-cc}"
"$CC" -std=c17 -O2 -DNDEBUG -Wall -Wextra -Wpedantic -Werror=implicit-function-declaration \
    -o app src/*.c
