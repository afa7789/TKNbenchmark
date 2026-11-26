#!/usr/bin/env bash
# Builds an optimized release binary and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release
cp target/release/wordfreq app
chmod +x app
