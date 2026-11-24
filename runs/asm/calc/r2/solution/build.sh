#!/usr/bin/env bash
# Build the release binary ./app from the AArch64 assembly sources.
set -euo pipefail
cd "$(dirname "$0")"
clang -arch arm64 -O2 -Wall -o app src/calc.s -Wl,-dead_strip
