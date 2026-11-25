#!/usr/bin/env bash
# Build the release binary ./app from the assembly sources.
set -euo pipefail
cd "$(dirname "$0")"
clang -O2 -o app src/*.s
