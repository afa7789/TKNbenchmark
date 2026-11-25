#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying the circuit can be generated for the input.
set -euo pipefail

input="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "$0")"

prover_name="Prover_input_$$"
prover_file="$prover_name.toml"
trap 'rm -f "$prover_file"' EXIT

# Convert the JSON input into a Prover.toml. Values are passed through as
# quoted strings; the circuit itself enforces every rule.
node -e '
const fs = require("fs");
const input = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const arr = (k) => {
  const v = input[k];
  if (!Array.isArray(v)) throw new Error(`"${k}" must be an array`);
  return "[" + v.map((x) => JSON.stringify(String(x))).join(", ") + "]";
};
fs.writeFileSync(process.argv[2], `puzzle = ${arr("puzzle")}\nsolution = ${arr("solution")}\n`);
' "$input" "$prover_file"

nargo execute --prover-name "$prover_name" >/dev/null
