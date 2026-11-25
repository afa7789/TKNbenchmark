#!/usr/bin/env bash
# Compiles the Sudoku circuit to R1CS and a WASM witness generator in build/.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

command -v circom >/dev/null || { echo "error: circom not found in PATH" >&2; exit 1; }
command -v node   >/dev/null || { echo "error: node not found in PATH" >&2; exit 1; }

rm -rf build
mkdir -p build
circom circuits/main/sudoku.circom --r1cs --wasm --sym --O2 --inspect -o build
