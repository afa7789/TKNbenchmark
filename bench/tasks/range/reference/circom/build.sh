#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
circom range.circom --wasm -o build >/dev/null
