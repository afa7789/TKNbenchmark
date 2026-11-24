#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness for the circuit can be generated from the given inputs.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 input.json" >&2
    exit 2
fi

input="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "${BASH_SOURCE[0]}")"

# nargo resolves the prover file by name relative to the package root.
prover_name="Prover_$$"
prover_file="${prover_name}.toml"
trap 'rm -f "$prover_file"' EXIT

# Translate the JSON object into a Prover.toml, passing each value through
# verbatim as a TOML string so the circuit (not this script) decides validity.
node -e '
const fs = require("fs");
const input = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (input === null || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("input must be a JSON object");
}
const lines = ["age", "threshold"].map((key) => {
    if (!(key in input)) throw new Error(`missing input: ${key}`);
    return `${key} = ${JSON.stringify(String(input[key]))}`;
});
fs.writeFileSync(process.argv[2], lines.join("\n") + "\n");
' "$input" "$prover_file"

nargo execute --prover-name "$prover_name" "witness_$$" >/dev/null
rm -f "target/witness_$$.gz"
