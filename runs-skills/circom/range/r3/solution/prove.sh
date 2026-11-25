#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying the circuit's constraints exists for the input.
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 input.json" >&2
    exit 2
fi

input="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "$0")"

if [ ! -f build/range_js/range.wasm ]; then
    echo "circuit not built; run build.sh first" >&2
    exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

node build/range_js/generate_witness.js build/range_js/range.wasm "$input" "$tmp/witness.wtns"
npx --no-install snarkjs wtns check build/range.r1cs "$tmp/witness.wtns" >"$tmp/check.log" 2>&1 || {
    cat "$tmp/check.log" >&2
    exit 1
}
