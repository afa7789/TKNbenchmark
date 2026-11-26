#!/usr/bin/env bash
# Builds the optimized release binary at ./app. Dependencies are fetched by cargo per Cargo.lock.
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release --locked
cp target/release/notes app
