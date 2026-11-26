#!/usr/bin/env bash
# Builds the optimized LRU simulator and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release --quiet
cp target/release/lru app
chmod +x app
