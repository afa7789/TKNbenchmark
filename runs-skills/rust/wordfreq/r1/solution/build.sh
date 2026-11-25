#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release
cp target/release/wordfreq ./app
