#!/usr/bin/env bash
# Compiles the Sudoku circuit to R1CS + WASM witness generator in build/.
set -euo pipefail
cd "$(dirname "$0")"

command -v circom >/dev/null || { echo "circom not found (need circom 2.2.3)" >&2; exit 1; }

mkdir -p build
circom circuits/main/sudoku.circom --r1cs --wasm --sym --O2 -o build
