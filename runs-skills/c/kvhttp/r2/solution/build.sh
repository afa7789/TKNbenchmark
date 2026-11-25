#!/usr/bin/env bash
# Build an optimized release binary at ./app. No third-party dependencies.
set -euo pipefail
cd "$(dirname "$0")"

CC="${CC:-cc}"
CFLAGS=(-std=c17 -O2 -DNDEBUG -Wall -Wextra -Wpedantic -Wshadow -Wconversion
        -Wstrict-prototypes -Wmissing-prototypes
        -fstack-protector-strong -D_FORTIFY_SOURCE=3 -ftrivial-auto-var-init=zero -pthread)
LDFLAGS=(-pthread)
[[ "$(uname -s)" == Darwin ]] && LDFLAGS+=(-Wl,-dead_strip)

"$CC" "${CFLAGS[@]}" src/main.c src/http.c src/kvstore.c "${LDFLAGS[@]}" -o app
