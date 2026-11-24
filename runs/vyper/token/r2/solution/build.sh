#!/usr/bin/env bash
# Compiles contracts/Token.vy and writes out/Token.json ({"abi": [...], "bytecode": "0x..."}).
set -euo pipefail
cd "$(dirname "$0")"

VYPER_VERSION="0.4.3"
CONTRACT="Token"
SRC="contracts/${CONTRACT}.vy"

if command -v vyper >/dev/null 2>&1 && [[ "$(vyper --version)" == "${VYPER_VERSION}"* ]]; then
  VYPER=(vyper)
elif command -v uvx >/dev/null 2>&1; then
  VYPER=(uvx "vyper==${VYPER_VERSION}")
else
  python3 -m venv .venv
  .venv/bin/pip install --quiet "vyper==${VYPER_VERSION}"
  VYPER=(.venv/bin/vyper)
fi

mkdir -p out
abi="$("${VYPER[@]}" -f abi "$SRC")"
bytecode="$("${VYPER[@]}" -f bytecode "$SRC")"
printf '{"abi": %s, "bytecode": "%s"}\n' "$abi" "$bytecode" > "out/${CONTRACT}.json"
echo "wrote out/${CONTRACT}.json"
