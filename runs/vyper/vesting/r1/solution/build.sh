#!/usr/bin/env bash
# Compile contracts/Vesting.vy into out/Vesting.json ({"abi": [...], "bytecode": "0x..."}).
set -euo pipefail
cd "$(dirname "$0")"

NAME=Vesting
SRC="contracts/${NAME}.vy"
VYPER="${VYPER:-vyper}"

mkdir -p out
"$VYPER" -f combined_json "$SRC" | python3 -c '
import json, sys
src, dst = sys.argv[1], sys.argv[2]
data = json.load(sys.stdin)[src]
with open(dst, "w") as f:
    json.dump({"abi": data["abi"], "bytecode": data["bytecode"]}, f)
' "$SRC" "out/${NAME}.json"
echo "wrote out/${NAME}.json"
