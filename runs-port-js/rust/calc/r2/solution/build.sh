#!/usr/bin/env bash
# Builds an optimized release binary and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release --locked --quiet
cp target/release/calc app
chmod +x app
