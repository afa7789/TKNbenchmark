#!/usr/bin/env bash
# Fetches dependencies and compiles the circuit to R1CS + WASM witness generator.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f package-lock.json ]]; then
    npm ci --no-audit --no-fund --silent
else
    npm install --no-audit --no-fund --silent
fi

mkdir -p build
circom range.circom --r1cs --wasm --sym -l node_modules -o build
