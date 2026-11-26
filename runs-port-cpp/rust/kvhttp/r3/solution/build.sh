#!/usr/bin/env bash
# Builds an optimised release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release --locked
cp target/release/app ./app
