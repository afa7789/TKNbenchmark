#!/usr/bin/env bash
# Builds an optimized release binary at ./app. No third-party dependencies.
set -euo pipefail
cd "$(dirname "$0")"

CXX="${CXX:-c++}"
"$CXX" -std=c++20 -O2 -DNDEBUG -Wall -Wextra -Wpedantic -pthread \
    src/http.cpp src/router.cpp src/main.cpp \
    -o app
