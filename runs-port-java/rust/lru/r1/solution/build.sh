#!/usr/bin/env bash
# Builds the LRU cache simulator as an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release --quiet
cp target/release/lru app
chmod +x app
