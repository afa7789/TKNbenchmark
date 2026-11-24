#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
vyper -f abi,bytecode token.vy | node -e 'const [abi,bytecode]=require("fs").readFileSync(0,"utf8").trim().split("\n");require("fs").writeFileSync("out/Token.json",JSON.stringify({abi:JSON.parse(abi),bytecode}))'
