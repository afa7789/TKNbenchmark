#!/usr/bin/env bash
# Build the release binary ./app from the assembly sources.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
clang -O2 -c src/wordfreq.s -o build/wordfreq.o
clang -O2 build/wordfreq.o -o app
