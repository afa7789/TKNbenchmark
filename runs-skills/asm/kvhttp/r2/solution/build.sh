#!/usr/bin/env bash
# Build the kvhttp server: assemble src/*.s and link against libSystem.
set -euo pipefail
cd "$(dirname "$0")"

CC=${CC:-clang}
ARCH_FLAGS=(-arch arm64 -mmacosx-version-min=11.0)

rm -rf build
mkdir -p build
for src in src/*.s; do
    "$CC" "${ARCH_FLAGS[@]}" -c "$src" -o "build/$(basename "${src%.s}").o"
done
"$CC" "${ARCH_FLAGS[@]}" -Wl,-dead_strip build/*.o -o app
