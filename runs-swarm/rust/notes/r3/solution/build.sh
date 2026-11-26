#!/usr/bin/env sh
# Builds the optimized release binary at ./app. Dependencies are fetched by cargo.
set -eu
cd "$(dirname "$0")"
cargo build --release --locked
cp target/release/notes app
