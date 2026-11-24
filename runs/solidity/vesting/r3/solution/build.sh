#!/usr/bin/env bash
# Compiles the Vesting contract and writes out/Vesting.json with {"abi": [...], "bytecode": "0x..."}.
set -euo pipefail
cd "$(dirname "$0")"

CONTRACT=Vesting

forge build --root . >/dev/null

mkdir -p out
abi=$(forge inspect --root . "$CONTRACT" abi --json)
bytecode=$(forge inspect --root . "$CONTRACT" bytecode)
printf '{"abi":%s,"bytecode":"%s"}\n' "$abi" "$bytecode" > "out/$CONTRACT.json"
