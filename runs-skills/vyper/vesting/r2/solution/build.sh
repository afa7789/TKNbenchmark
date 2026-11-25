#!/usr/bin/env bash
# Compile src/Vesting.vy and write out/Vesting.json ({"abi": [...], "bytecode": "0x..."}).
set -euo pipefail
cd "$(dirname "$0")"

VYPER="${VYPER:-vyper}"
if ! command -v "$VYPER" >/dev/null 2>&1; then
    echo "vyper not found; install with: pip install vyper==0.4.3" >&2
    exit 1
fi

mkdir -p out
abi="$("$VYPER" -f abi src/Vesting.vy)"
bytecode="$("$VYPER" -f bytecode src/Vesting.vy)"
printf '{"abi": %s, "bytecode": "%s"}\n' "$abi" "$bytecode" > out/Vesting.json
echo "wrote out/Vesting.json"
