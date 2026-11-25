#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying the circuit can be generated for the inputs.
set -euo pipefail

input=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$(dirname "$0")"

prover=$(mktemp "./prover-XXXXXX")
trap 'rm -f "$prover" "$prover.toml"' EXIT

# JSON -> TOML. Values are emitted as quoted decimal strings; anything that is
# not a 16-element array of decimal strings is rejected up front.
jq -er '
  def cells($k):
    .[$k] as $v
    | if ($v | type) == "array" and ($v | length) == 16
         and all($v[]; type == "string" and test("^[0-9]+$"))
      then "\($k) = [\($v | map(tojson) | join(", "))]"
      else error("\($k) must be an array of 16 decimal strings") end;
  cells("puzzle"), cells("solution")
' "$input" > "$prover.toml"

nargo execute --prover-name "$(basename "$prover")" sudoku-witness
