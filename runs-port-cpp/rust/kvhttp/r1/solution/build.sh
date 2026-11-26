#!/usr/bin/env bash
# Builds an optimized release binary at ./app. No third-party dependencies.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release
cp target/release/kvhttp app
