#!/usr/bin/env bash
# Build an optimized release binary and place it at ./app.
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release --locked --quiet
cp target/release/wordfreq ./app
