#!/usr/bin/env bash
# Build kvhttp in release mode and install the binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release --locked
cp target/release/kvhttp app
chmod +x app
