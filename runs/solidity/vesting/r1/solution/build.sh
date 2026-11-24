#!/usr/bin/env bash
# Compiles Vesting and writes out/Vesting.json with {"abi": [...], "bytecode": "0x..."}.
set -euo pipefail
cd "$(dirname "$0")"

forge build --quiet

mkdir -p out
node -e '
const fs = require("fs");
const art = JSON.parse(fs.readFileSync("forge-out/Vesting.sol/Vesting.json", "utf8"));
fs.writeFileSync("out/Vesting.json", JSON.stringify({ abi: art.abi, bytecode: art.bytecode.object }, null, 2) + "\n");
'
