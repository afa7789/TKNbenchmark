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
trap 'rm -f "${prover}.toml"' EXIT

# Convert the JSON object into a Prover.toml. Values are emitted as quoted TOML
# strings and validated by nargo's ABI encoder and by the circuit itself; no
# range logic lives here.
node -e '
const fs = require("fs");
const input = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const lines = [];
for (const key of ["age", "threshold"]) {
  if (!(key in input)) { console.error(`missing input: ${key}`); process.exit(1); }
  lines.push(`${key} = ${JSON.stringify(String(input[key]))}`);
}
fs.writeFileSync(process.argv[2], lines.join("\n") + "\n");
' "$input" "${prover}.toml"

nargo execute --prover-name "$prover"
