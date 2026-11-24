#!/usr/bin/env bash
# Build the wordfreq release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
clang -arch arm64 -O2 -Wall -Wl,-dead_strip -o app wordfreq.s
