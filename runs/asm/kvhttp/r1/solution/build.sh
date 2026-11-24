#!/usr/bin/env bash
# Build the kvhttp release binary at ./app from the AArch64 sources in src/.
set -euo pipefail
cd "$(dirname "$0")"

CC=${CC:-clang}
"$CC" -arch arm64 -mcpu=apple-m1 -O2 -I src \
    -Wl,-dead_strip \
    -o app src/main.s src/conn.s src/http.s src/store.s
strip -x app 2>/dev/null || true
