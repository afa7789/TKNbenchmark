#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
forge build --silent --out .forge-out
mkdir -p out
node -e 'const j=require("./.forge-out/Vesting.sol/Vesting.json");require("fs").writeFileSync("out/Vesting.json",JSON.stringify({abi:j.abi,bytecode:j.bytecode.object}))'
