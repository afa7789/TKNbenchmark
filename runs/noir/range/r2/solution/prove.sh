#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Generates a witness for {"age": "...", "threshold": "..."}; exits non-zero
# if the inputs do not satisfy the circuit. All rules are enforced in-circuit;
# this script only translates JSON into a Prover TOML file.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 input.json" >&2
  exit 2
fi

input="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "${BASH_SOURCE[0]}")"

prover_name="Prover_$$"
trap 'rm -f "${prover_name}.toml"' EXIT

# JSON string literals are valid TOML basic strings, so values are quoted safely.
node -e '
const fs = require("fs");
const input = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const lines = ["age", "threshold"].map((k) => {
  if (!(k in input)) throw new Error(`missing input: ${k}`);
  return `${k} = ${JSON.stringify(String(input[k]))}`;
});
fs.writeFileSync(process.argv[2], lines.join("\n") + "\n");
' "$input" "${prover_name}.toml"

nargo execute --prover-name "$prover_name" "witness_$$" >/dev/null
rm -f "target/witness_$$.gz"
