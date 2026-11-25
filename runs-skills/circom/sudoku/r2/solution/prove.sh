#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 if a witness exists for the input, meaning every circuit constraint
# holds. Exits non-zero otherwise.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 1 ]]; then
    echo "usage: bash prove.sh input.json" >&2
    exit 2
fi
input="$1"
[[ -f "$input" ]] || { echo "error: input file not found: $input" >&2; exit 2; }

js="$here/build/sudoku_js"
[[ -f "$js/sudoku.wasm" ]] || { echo "error: circuit not built; run build.sh first" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The WASM witness calculator checks every constraint and fails on any
# violation.
node "$js/generate_witness.js" "$js/sudoku.wasm" "$input" "$tmp/witness.wtns"
