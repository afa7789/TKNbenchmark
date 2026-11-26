#!/usr/bin/env bash
# Builds kvhttp in release mode and places the binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release --locked
cp target/release/kvhttp app
chmod +x app
