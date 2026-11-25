#!/usr/bin/env bash
# Compiles src/Vesting.vy and writes out/Vesting.json with {"abi", "bytecode"}.
set -euo pipefail
cd "$(dirname "$0")"

VYPER_VERSION="0.4.3"
if command -v vyper >/dev/null 2>&1 && vyper --version | grep -q "^${VYPER_VERSION}"; then
    VYPER=(vyper)
elif command -v uvx >/dev/null 2>&1; then
    VYPER=(uvx "vyper==${VYPER_VERSION}")
else
    echo "vyper ${VYPER_VERSION} not found (install it or uv)" >&2
    exit 1
fi

mkdir -p out
abi=$("${VYPER[@]}" -f abi src/Vesting.vy)
bytecode=$("${VYPER[@]}" -f bytecode src/Vesting.vy)
printf '{"abi": %s, "bytecode": "%s"}\n' "$abi" "$bytecode" > out/Vesting.json
