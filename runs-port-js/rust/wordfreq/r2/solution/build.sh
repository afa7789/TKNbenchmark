#!/usr/bin/env bash
# Builds an optimized release binary of wordfreq and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release --locked --quiet
cp target/release/wordfreq app
chmod +x app
