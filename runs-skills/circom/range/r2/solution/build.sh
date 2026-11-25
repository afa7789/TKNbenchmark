#!/usr/bin/env bash
# Compiles the range circuit to R1CS + WASM witness generator in build/.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ -f package-lock.json ]; then
    npm ci --no-audit --no-fund --silent
else
    npm install --no-audit --no-fund --silent
fi

mkdir -p build
circom circuits/main/range.circom --r1cs --wasm --sym -l node_modules -o build
