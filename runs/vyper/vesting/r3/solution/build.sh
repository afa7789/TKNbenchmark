#!/usr/bin/env bash
# Compiles contracts/Vesting.vy into out/Vesting.json ({"abi": [...], "bytecode": "0x..."}).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

VYPER="${VYPER:-vyper}"
CONTRACT=Vesting
SRC="contracts/${CONTRACT}.vy"
OUT="out/${CONTRACT}.json"

mkdir -p out
abi="$("$VYPER" -f abi "$SRC")"
bytecode="$("$VYPER" -f bytecode "$SRC")"
printf '{"abi": %s, "bytecode": "%s"}\n' "$abi" "$bytecode" > "$OUT"
echo "wrote $OUT"
