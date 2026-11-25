#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying the circuit can be generated for the input.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 input.json" >&2
    exit 2
fi

input="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "$0")"

js=build/sudoku_js
[[ -f $js/sudoku.wasm ]] || { echo "circuit not built; run build.sh" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

node "$js/generate_witness.js" "$js/sudoku.wasm" "$input" "$tmp/witness.wtns"
