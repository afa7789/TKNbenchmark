#!/usr/bin/env bash
# Builds an optimized release binary and installs it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release --locked --quiet
cp target/release/wordfreq app
chmod +x app
