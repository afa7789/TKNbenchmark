#!/usr/bin/env bash
# Compiles contracts/Token.vy and writes out/Token.json ({"abi": [...], "bytecode": "0x..."}).
set -euo pipefail

VYPER_VERSION="0.4.3"
cd "$(dirname "${BASH_SOURCE[0]}")"

# Use a matching system vyper if available; otherwise install a pinned copy in a local venv.
VYPER="$(command -v vyper || true)"
if [[ -z "$VYPER" ]] || [[ "$("$VYPER" --version)" != "$VYPER_VERSION"* ]]; then
    if [[ ! -x .venv/bin/vyper ]]; then
        python3 -m venv .venv
        .venv/bin/pip install --quiet "vyper==${VYPER_VERSION}"
    fi
    VYPER=.venv/bin/vyper
fi

mkdir -p out
"$VYPER" -f abi,bytecode contracts/Token.vy | python3 -c '
import json, sys
abi, bytecode = sys.stdin.read().strip().split("\n", 1)
json.dump({"abi": json.loads(abi), "bytecode": bytecode.strip()}, sys.stdout, indent=2)
' > out/Token.json
