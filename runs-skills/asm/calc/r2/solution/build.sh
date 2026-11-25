#!/usr/bin/env bash
# Build the calc release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
for src in src/*.s; do
    clang -c -O2 "$src" -o "build/$(basename "${src%.s}").o"
done
clang -O2 build/*.o -o app
