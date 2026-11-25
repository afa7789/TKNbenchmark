#!/usr/bin/env bash
# Compiles src/Token.vy and writes out/Token.json with {"abi": [...], "bytecode": "0x..."}.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

VYPER_VERSION="0.4.3"
CONTRACT="Token"

if command -v vyper >/dev/null 2>&1 && [[ "$(vyper --version)" == "${VYPER_VERSION}"* ]]; then
    VYPER=(vyper)
elif command -v uvx >/dev/null 2>&1; then
    VYPER=(uvx --from "vyper==${VYPER_VERSION}" vyper)
else
    python3 -m venv .venv
    .venv/bin/pip install --quiet "vyper==${VYPER_VERSION}"
    VYPER=(.venv/bin/vyper)
fi

mkdir -p out
abi="$("${VYPER[@]}" -f abi "src/${CONTRACT}.vy")"
bytecode="$("${VYPER[@]}" -f bytecode "src/${CONTRACT}.vy")"

python3 - "$abi" "$bytecode" "out/${CONTRACT}.json" <<'PY'
import json, sys
abi, bytecode, path = sys.argv[1], sys.argv[2].strip(), sys.argv[3]
with open(path, "w") as f:
    json.dump({"abi": json.loads(abi), "bytecode": bytecode}, f, indent=2)
    f.write("\n")
PY
