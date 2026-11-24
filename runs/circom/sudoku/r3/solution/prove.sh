#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying every circuit constraint can be generated for the input.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 input.json" >&2
    exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
js="$root/build/main_js"
[[ -f "$js/main.wasm" ]] || { echo "error: circuit not built; run build.sh first" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The witness calculator evaluates every `===` constraint and fails on any violation.
node "$js/generate_witness.js" "$js/main.wasm" "$1" "$tmp/witness.wtns"
