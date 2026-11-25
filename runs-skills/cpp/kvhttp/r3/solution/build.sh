#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

generator=()
if command -v ninja >/dev/null 2>&1; then
  generator=(-G Ninja)
fi

cmake -S . -B build/release "${generator[@]}" -DCMAKE_BUILD_TYPE=Release -DKVHTTP_WERROR=ON
cmake --build build/release --parallel
cp build/release/app ./app
