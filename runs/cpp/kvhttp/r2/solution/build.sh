#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

SOURCES=(src/main.cpp src/http.cpp src/server.cpp src/routes.cpp)

if command -v cmake >/dev/null 2>&1; then
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build build --parallel >/dev/null
  cp build/app ./app
else
  "${CXX:-c++}" -std=c++20 -O2 -DNDEBUG -Wall -Wextra -Wpedantic -pthread \
    "${SOURCES[@]}" -o app
fi
