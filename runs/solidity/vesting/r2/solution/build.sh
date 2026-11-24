#!/usr/bin/env bash
# Compiles the Vesting contract and writes out/Vesting.json with {"abi": [...], "bytecode": "0x..."}.
set -euo pipefail
cd "$(dirname "$0")"

CONTRACT=Vesting

forge build --quiet

mkdir -p out
node -e '
const fs = require("fs");
const [src, dst] = process.argv.slice(1);
const art = JSON.parse(fs.readFileSync(src, "utf8"));
fs.writeFileSync(dst, JSON.stringify({ abi: art.abi, bytecode: art.bytecode.object }, null, 2) + "\n");
' "forge-out/${CONTRACT}.sol/${CONTRACT}.json" "out/${CONTRACT}.json"
