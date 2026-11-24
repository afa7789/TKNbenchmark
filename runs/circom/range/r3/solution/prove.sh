#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying all circuit constraints can be generated.
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -ne 1 ]]; then
    echo "usage: $0 input.json" >&2
    exit 2
fi
input=$(cd "$OLDPWD" && realpath "$1")

wasm_dir=build/range_js
if [[ ! -f "$wasm_dir/range.wasm" ]]; then
    echo "circuit not built; run build.sh first" >&2
    exit 2
fi

# The witness calculator silently reduces inputs modulo the field prime, so
# reject anything that is not a canonical field element encoding up front;
# otherwise e.g. p + 25 would be indistinguishable from 25.
node - "$input" <<'JS'
const fs = require('fs')
const P = 21888242871839275222246405745257275088548364400416034343698204186575808495617n
const input = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
for (const key of ['age', 'threshold']) {
  const v = input[key]
  if (typeof v !== 'string' && typeof v !== 'number') throw new Error(`${key}: missing or not a scalar`)
  const s = String(v).trim()
  if (!/^[0-9]+$/.test(s) || BigInt(s) >= P) throw new Error(`${key}: not a canonical field element: ${s}`)
}
JS

witness=$(mktemp -t range-witness.XXXXXX)
trap 'rm -f "$witness"' EXIT
node "$wasm_dir/generate_witness.js" "$wasm_dir/range.wasm" "$input" "$witness"
