#!/usr/bin/env bash
# Builds the kvhttp release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
for src in src/*.s; do
    clang -c -O2 -arch arm64 -mmacosx-version-min=13.0 "$src" -o "build/$(basename "${src%.s}").o"
done
clang -arch arm64 -mmacosx-version-min=13.0 -Wl,-dead_strip build/*.o -o app
