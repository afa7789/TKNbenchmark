#!/usr/bin/env bash
# Builds the optimized release binary at ./app. Dependencies are fetched by cargo (pinned by Cargo.lock).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
cargo build --release --locked
cp target/release/notes ./app
