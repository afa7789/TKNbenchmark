#!/usr/bin/env bash
# Build the kvhttp server (AArch64 assembly, macOS) into ./app.
set -euo pipefail
cd "$(dirname "$0")"

CC=${CC:-clang}
ARCHFLAGS=(-arch arm64 -mmacosx-version-min=12.0)

rm -rf build
mkdir -p build
for src in src/*.s; do
    "$CC" "${ARCHFLAGS[@]}" -c "$src" -o "build/$(basename "${src%.s}").o"
done
"$CC" "${ARCHFLAGS[@]}" -Wl,-dead_strip build/*.o -o app
