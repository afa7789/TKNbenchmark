#!/usr/bin/env bash
# Build the kvhttp release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
clang -arch arm64 -O2 -Wl,-dead_strip -o app src/main.s src/http.s src/store.s
