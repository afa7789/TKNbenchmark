#!/usr/bin/env bash
# Build an optimized release binary at ./app.
#
# Every *.c file under src/ is compiled, so a subcommand module may add
# source files inside its own directory without touching this script.
set -euo pipefail

cd "$(dirname "$0")"

CC=${CC:-cc}
CFLAGS=(-std=c17 -O2 -DNDEBUG -Wall -Wextra -Wpedantic -Isrc)

sources=()
while IFS= read -r -d '' f; do
    sources+=("$f")
done < <(find src -type f -name '*.c' -print0 | sort -z)

"$CC" "${CFLAGS[@]}" -o app "${sources[@]}"
