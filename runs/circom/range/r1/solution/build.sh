#!/usr/bin/env bash
# Fetches dependencies and compiles the circuit to R1CS + WASM witness generator.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ -f package-lock.json ]]; then
    npm ci --no-audit --no-fund --loglevel=error
else
    npm install --no-audit --no-fund --loglevel=error
fi

mkdir -p build
circom circuits/range.circom \
    --r1cs --wasm --sym \
    -l node_modules \
    -o build
