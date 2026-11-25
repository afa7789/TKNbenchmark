#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying every circuit constraint exists for the input.
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

wtns="$(mktemp -t range.XXXXXX)"
trap 'rm -f "$wtns"' EXIT

# Witness generation fails on any violated constraint.
node build/range_js/generate_witness.js build/range_js/range.wasm "$input" "$wtns"
# Independently re-check the witness against the R1CS.
npx --no-install snarkjs wtns check build/range.r1cs "$wtns" >/dev/null
