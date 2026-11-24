#!/usr/bin/env bash
# Builds an optimized release binary at ./app. No third-party dependencies.
set -euo pipefail
cd "$(dirname "$0")"

CC="${CC:-cc}"
CFLAGS=(-std=c17 -O2 -DNDEBUG -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wno-sign-conversion)

"$CC" "${CFLAGS[@]}" -o app src/main.c src/server.c src/http.c src/routes.c src/store.c
