#!/usr/bin/env bash
# Compile the range circuit to R1CS + WASM witness generator in build/.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d node_modules/circomlib ] || [ ! -d node_modules/snarkjs ]; then
    npm install --no-audit --no-fund --loglevel=error
fi

mkdir -p build
circom circuits/main/range.circom --r1cs --wasm --sym -l node_modules -o build
