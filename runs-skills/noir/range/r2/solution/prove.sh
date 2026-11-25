#!/usr/bin/env bash
# Usage: bash prove.sh input.json
# Exits 0 iff a witness satisfying the circuit can be generated for the input.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 input.json" >&2
    exit 2
fi

input="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "$0")"

prover_name="input-$$"
prover_file="${prover_name}.toml"
trap 'rm -f "$prover_file"' EXIT

# Translate the JSON object into a Prover.toml-style file. Values are passed
# through verbatim as TOML strings; range checking is done by the circuit.
node - "$input" "$prover_file" <<'JS'
const fs = require('node:fs')
const [input, out] = process.argv.slice(2)
const data = JSON.parse(fs.readFileSync(input, 'utf8'))
const lines = ['age', 'threshold'].map((key) => {
  const v = data?.[key]
  if (typeof v !== 'string' && typeof v !== 'number' && typeof v !== 'bigint') {
    console.error(`missing or invalid "${key}"`)
    process.exit(1)
  }
  return `${key} = ${JSON.stringify(String(v))}`
})
fs.writeFileSync(out, lines.join('\n') + '\n')
JS

nargo execute --prover-name "$prover_name"
