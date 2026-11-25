#!/usr/bin/env bash
# Compiles the Sudoku circuit to R1CS + WASM witness generator in ./build.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
circom circuits/main/sudoku.circom --r1cs --wasm --sym --O2 --inspect -o build
