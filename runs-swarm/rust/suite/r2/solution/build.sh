#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release --locked --quiet
cp target/release/app ./app
