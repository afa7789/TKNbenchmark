#!/usr/bin/env bash
# Builds the kvhttp server in release mode and places the binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release --locked
# Replace rather than overwrite in place: macOS kills processes whose signed binary was modified.
rm -f app
cp target/release/kvhttp app
