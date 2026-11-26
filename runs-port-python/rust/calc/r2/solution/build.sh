#!/usr/bin/env bash
# Build an optimized release binary and place it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release --offline --quiet
cp target/release/calc app
chmod +x app
