#!/usr/bin/env bash
# Build an optimized release binary and install it as ./app.
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release --quiet
cp target/release/lru app
chmod +x app
