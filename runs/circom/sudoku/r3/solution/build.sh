#!/usr/bin/env bash
# Compiles the Sudoku circuit to R1CS and a WebAssembly witness generator in ./build.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

command -v circom >/dev/null || { echo "error: circom 2 not found in PATH" >&2; exit 1; }

rm -rf build
mkdir -p build
circom circuits/main.circom --r1cs --wasm --sym -o build
