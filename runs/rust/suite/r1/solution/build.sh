#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release --quiet
cp target/release/suite ./app
