#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying every circuit constraint can be generated.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 input.json" >&2
    exit 2
fi

input="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "$0")"

wasm_dir=build/sudoku_js
if [[ ! -f "$wasm_dir/sudoku.wasm" ]]; then
    echo "circuit not built; run build.sh first" >&2
    exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

node "$wasm_dir/generate_witness.js" "$wasm_dir/sudoku.wasm" "$input" "$tmp/witness.wtns"
