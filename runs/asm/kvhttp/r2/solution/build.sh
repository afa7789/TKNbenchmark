#!/usr/bin/env bash
# Build the kvhttp release binary at ./app (AArch64 macOS, no dependencies).
set -euo pipefail
cd "$(dirname "$0")"
exec clang -arch arm64 -O2 -Wall -I src -Wl,-dead_strip -o app src/*.s
