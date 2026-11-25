#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying the circuit can be generated for the inputs.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 input.json" >&2
  exit 2
fi

input="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "${BASH_SOURCE[0]}")"

prover="Prover_$$"
trap 'rm -f "$prover.toml"' EXIT

# Convert the JSON object into a Prover TOML file; values stay quoted decimal strings.
node -e '
const fs = require("fs");
const input = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const lines = ["puzzle", "solution"].map((key) => {
  const v = input[key];
  if (!Array.isArray(v)) throw new Error(`missing array "${key}"`);
  return `${key} = [${v.map((x) => JSON.stringify(String(x))).join(", ")}]`;
});
fs.writeFileSync(process.argv[2], lines.join("\n") + "\n");
' "$input" "$prover.toml"

nargo execute --prover-name "$prover"
