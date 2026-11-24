#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying the circuit's constraints can be generated.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ $# -ne 1 ]]; then
    echo "usage: $0 input.json" >&2
    exit 2
fi

input="$1"
[[ "$input" = /* ]] || input="$OLDPWD/$input"

wasm_dir=build/range_js
if [[ ! -f "$wasm_dir/range.wasm" ]]; then
    echo "error: circuit not built; run build.sh first" >&2
    exit 2
fi

wtns="$(mktemp -t range-wtns.XXXXXX)"
trap 'rm -f "$wtns"' EXIT

node "$wasm_dir/generate_witness.js" "$wasm_dir/range.wasm" "$input" "$wtns"
