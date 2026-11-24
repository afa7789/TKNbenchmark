#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying every circuit constraint exists for the input.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 input.json" >&2
  exit 2
fi
[ -f "$1" ] || { echo "error: input file not found: $1" >&2; exit 2; }
input=$(realpath "$1")
cd "$(dirname "$0")"

wasm_dir=build/sudoku_js
r1cs=build/sudoku.r1cs
if [ ! -f "$wasm_dir/sudoku.wasm" ] || [ ! -f "$r1cs" ]; then
  echo "error: circuit not built; run build.sh first" >&2
  exit 2
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Witness generation fails on any violated assertion/constraint.
node "$wasm_dir/generate_witness.js" "$wasm_dir/sudoku.wasm" "$input" "$tmp/witness.wtns"
# Independently verify the witness against the compiled R1CS.
node_modules/.bin/snarkjs wtns check "$r1cs" "$tmp/witness.wtns"
