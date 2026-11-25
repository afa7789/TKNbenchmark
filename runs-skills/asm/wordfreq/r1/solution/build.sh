#!/usr/bin/env bash
# Build the release binary ./app from the AArch64 assembly sources.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
for src in src/*.s; do
    clang -arch arm64 -c "$src" -o "build/$(basename "${src%.s}").o"
done
clang -arch arm64 -Wl,-dead_strip build/*.o -o app
