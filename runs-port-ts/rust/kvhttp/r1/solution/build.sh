#!/usr/bin/env bash
# Builds an optimized release binary and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

command -v cargo >/dev/null || { echo "cargo is required" >&2; exit 1; }

cargo build --release --locked
cp target/release/kvhttp app
chmod +x app
