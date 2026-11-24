#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff the inputs satisfy the circuit (a witness can be generated).
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 input.json" >&2
  exit 2
fi
input=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$(dirname "${BASH_SOURCE[0]}")"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Convert the JSON input into a nargo prover file. Values are passed through
# verbatim; nargo itself rejects anything that does not fit the ABI types.
jq -er '
  "puzzle = \(.puzzle | tojson)",
  "solution = \(.solution | tojson)"
' "$input" > "$tmp/Prover.toml"

nargo execute --prover-name "$tmp/Prover" "$tmp/witness" >/dev/null
