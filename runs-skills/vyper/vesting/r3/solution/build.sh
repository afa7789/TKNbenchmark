#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
vyper -f abi,bytecode src/Vesting.vy | python3 -c '
import json, sys
abi, bytecode = sys.stdin.read().strip().split("\n", 1)
json.dump({"abi": json.loads(abi), "bytecode": bytecode.strip()}, open("out/Vesting.json", "w"))
'
