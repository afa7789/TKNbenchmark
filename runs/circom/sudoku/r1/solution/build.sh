#!/usr/bin/env bash
# Compiles the Sudoku circuit to R1CS + WASM witness generator in ./build.
set -euo pipefail
cd "$(dirname "$0")"

command -v circom >/dev/null || { echo "error: circom not found in PATH" >&2; exit 1; }

# snarkjs is used by prove.sh to check the witness against the R1CS.
if [ ! -x node_modules/.bin/snarkjs ]; then
  npm install --no-audit --no-fund --silent
fi

mkdir -p build
circom circuits/sudoku.circom --r1cs --wasm --sym -o build
