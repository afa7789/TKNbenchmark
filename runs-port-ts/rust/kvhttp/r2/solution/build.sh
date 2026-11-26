#!/usr/bin/env bash
# Builds an optimized release binary and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release --locked 2>&1 || cargo build --release
cp target/release/kvhttp app
chmod +x app
