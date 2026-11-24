#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
vyper -f abi,bytecode vesting.vy | node -e 'const [abi,bytecode]=require("fs").readFileSync(0,"utf8").trim().split("\n");require("fs").writeFileSync("out/Vesting.json",JSON.stringify({abi:JSON.parse(abi),bytecode}))'
