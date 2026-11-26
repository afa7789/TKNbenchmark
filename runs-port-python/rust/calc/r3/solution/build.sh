#!/usr/bin/env bash
# Build the optimized calc release binary and install it as ./app.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release --quiet
cp target/release/calc app
chmod +x app
