#!/usr/bin/env bash
# Builds the optimized calc binary and installs it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release
cp target/release/calc app
chmod +x app
