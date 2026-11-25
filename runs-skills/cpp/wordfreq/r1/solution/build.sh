#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
clang++ -std=c++20 -O2 -DNDEBUG -Wall -Wextra -Wpedantic -Wshadow -Wconversion \
  -Wsign-conversion -o app src/main.cpp
