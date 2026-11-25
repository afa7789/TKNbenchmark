#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying every circuit constraint exists for the input.
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 input.json" >&2
    exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
input="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
build="$root/build"

if [ ! -f "$build/range_js/range.wasm" ]; then
    echo "circuit not built; run build.sh first" >&2
    exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Witness generation fails if any constraint is violated.
node "$build/range_js/generate_witness.js" "$build/range_js/range.wasm" "$input" "$tmp/witness.wtns"
# Independently re-check the witness against the R1CS.
"$root/node_modules/.bin/snarkjs" wtns check "$build/range.r1cs" "$tmp/witness.wtns" >/dev/null
