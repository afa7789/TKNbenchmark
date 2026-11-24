#!/usr/bin/env bash
# Builds an optimised release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

if command -v cmake >/dev/null 2>&1; then
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build build --parallel
  cp build/app ./app
else
  "${CXX:-c++}" -std=c++20 -O2 -DNDEBUG -Wall -Wextra -Wpedantic -pthread \
    src/main.cpp src/http.cpp src/router.cpp -o app
fi
