#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying every circuit constraint can be generated
# for the given inputs. Run build.sh first.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 input.json" >&2
    exit 2
fi
input=$1
[[ -f $input ]] || { echo "error: input file not found: $input" >&2; exit 2; }
input=$(cd "$(dirname "$input")" && pwd)/$(basename "$input")
cd "$(dirname "${BASH_SOURCE[0]}")"

js_dir=build/sudoku_js
[[ -f $js_dir/sudoku.wasm ]] || { echo "error: circuit not built; run build.sh" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The WASM witness calculator checks every constraint and fails if any is violated.
node "$js_dir/generate_witness.js" "$js_dir/sudoku.wasm" "$input" "$tmp/witness.wtns"
echo "witness generated: inputs satisfy the circuit"
