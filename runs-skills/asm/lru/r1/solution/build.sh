#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
clang -O2 -c src/lru.S -o build/lru.o
clang -O2 build/lru.o -o app
