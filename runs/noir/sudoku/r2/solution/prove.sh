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

prover="Prover_$$_$RANDOM"
trap 'rm -f "$prover.toml"' EXIT

# Translate the JSON input into a Prover.toml. Only shape is validated here;
# all Sudoku rules are enforced by the circuit itself.
node - "$input" "$prover.toml" <<'JS'
const fs = require('node:fs')
const [inputPath, outPath] = process.argv.slice(2)
const input = JSON.parse(fs.readFileSync(inputPath, 'utf8'))
const field = (name) => {
  const v = input[name]
  if (!Array.isArray(v) || v.length !== 16 || !v.every((x) => /^\d+$/.test(String(x)))) {
    throw new Error(`${name} must be an array of 16 decimal strings`)
  }
  return `${name} = [${v.map((x) => JSON.stringify(String(x))).join(', ')}]`
}
fs.writeFileSync(outPath, `${field('puzzle')}\n${field('solution')}\n`)
JS

nargo execute --prover-name "$prover" >/dev/null
