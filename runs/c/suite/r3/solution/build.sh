#!/usr/bin/env bash
# Build the optimized release binary ./app from the sources in src/.
set -euo pipefail
cd "$(dirname "$0")"

CC=${CC:-cc}
CFLAGS=(-std=c17 -O2 -DNDEBUG -Wall -Wextra -Wpedantic)

"$CC" "${CFLAGS[@]}" -o app src/*.c
