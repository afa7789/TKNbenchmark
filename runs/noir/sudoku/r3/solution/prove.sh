#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying the circuit can be generated for the inputs.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 input.json" >&2
    exit 2
fi

input="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "$0")"

prover="prover-$$"
trap 'rm -f "$prover.toml"' EXIT

# Translate the JSON input into a Prover.toml; every value is passed through as a
# string so that nargo (and the circuit) performs all parsing and validation.
jq -er '
  def arr(k): if (.[k] | type) == "array"
              then "\(k) = [" + (.[k] | map(tostring | tojson) | join(", ")) + "]"
              else error("\(k) must be an array") end;
  arr("puzzle"), arr("solution")
' "$input" > "$prover.toml"

nargo execute --prover-name "$prover" --silence-warnings
