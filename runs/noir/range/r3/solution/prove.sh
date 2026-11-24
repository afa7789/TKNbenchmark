#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying the circuit can be generated for the inputs.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 input.json" >&2
  exit 2
fi

input=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$(dirname "${BASH_SOURCE[0]}")"

# nargo resolves the prover file relative to the package root; use a unique name
# so concurrent runs do not clobber each other.
prover="Prover_$$"
trap 'rm -f "$prover.toml"' EXIT

# Translate the JSON object into Prover.toml. Values are passed through verbatim
# as TOML strings; all validation happens in the circuit.
node -e '
const fs = require("fs");
const input = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const lines = ["age", "threshold"].map((k) => {
  if (!(k in input)) throw new Error(`missing input: ${k}`);
  return `${k} = ${JSON.stringify(String(input[k]))}`;
});
fs.writeFileSync(process.argv[2], lines.join("\n") + "\n");
' "$input" "$prover.toml"

nargo execute --prover-name "$prover" --silence-warnings
