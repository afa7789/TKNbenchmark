#!/usr/bin/env bash
# Compiles src/Token.vy and writes out/Token.json with {"abi": [...], "bytecode": "0x..."}.
set -euo pipefail
cd "$(dirname "$0")"

VYPER="${VYPER:-vyper}"
mkdir -p out

abi="$("$VYPER" -f abi src/Token.vy)"
bytecode="$("$VYPER" -f bytecode src/Token.vy)"

printf '{"abi": %s, "bytecode": "%s"}\n' "$abi" "$bytecode" > out/Token.json
echo "wrote out/Token.json"
