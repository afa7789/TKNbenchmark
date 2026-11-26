#!/usr/bin/env bash
# Build an optimized release binary and place it at ./app.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
cargo build --release --quiet
cp target/release/suite ./app
