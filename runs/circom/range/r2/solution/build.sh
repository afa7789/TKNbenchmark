#!/usr/bin/env bash
# Compiles circuits/range.circom to R1CS + WASM witness generator in build/.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

command -v circom >/dev/null || { echo "error: circom not found in PATH" >&2; exit 1; }
command -v npm    >/dev/null || { echo "error: npm not found in PATH" >&2; exit 1; }

# Fetch circomlib (pinned in package.json / package-lock.json).
if [[ -f package-lock.json ]]; then
    npm ci --silent --no-audit --no-fund
else
    npm install --silent --no-audit --no-fund
fi

mkdir -p build
circom circuits/range.circom --r1cs --wasm --sym -l node_modules -o build
