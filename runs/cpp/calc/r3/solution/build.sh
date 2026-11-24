#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
c++ -std=c++20 -O2 -DNDEBUG -Wall -Wextra -Wpedantic -o app main.cpp
