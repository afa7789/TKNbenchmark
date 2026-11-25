#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

build_dir=build
generator=()
if command -v ninja >/dev/null 2>&1; then
  generator=(-G Ninja)
fi

cmake -S . -B "$build_dir" "${generator[@]}" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$build_dir" --config Release
cp "$build_dir/app" ./app
