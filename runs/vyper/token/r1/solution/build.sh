#!/usr/bin/env bash
# Compiles contracts/Token.vy and writes out/Token.json ({"abi": [...], "bytecode": "0x..."}).
# Uses a vyper 0.4.3 on PATH if present; otherwise installs it into a local virtualenv.
set -euo pipefail

VYPER_VERSION="0.4.3"
CONTRACT="Token"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

vyper_bin=""
if command -v vyper >/dev/null 2>&1 && vyper --version 2>/dev/null | grep -q "^${VYPER_VERSION}"; then
    vyper_bin="$(command -v vyper)"
else
    venv="$ROOT/.venv"
    if [[ ! -x "$venv/bin/vyper" ]]; then
        python3 -m venv "$venv"
        "$venv/bin/pip" install --quiet "vyper==${VYPER_VERSION}"
    fi
    vyper_bin="$venv/bin/vyper"
fi

mkdir -p out
abi="$("$vyper_bin" -f abi "contracts/${CONTRACT}.vy")"
bytecode="$("$vyper_bin" -f bytecode "contracts/${CONTRACT}.vy")"

printf '{"abi": %s, "bytecode": "%s"}\n' "$abi" "$bytecode" > "out/${CONTRACT}.json"
echo "wrote out/${CONTRACT}.json"
