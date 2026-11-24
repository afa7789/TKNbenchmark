#!/usr/bin/env bash
# Builds the Token contract and writes out/Token.json ({abi, bytecode}).
set -euo pipefail
cd "$(dirname "$0")"

OZ_VERSION="v5.1.0"
OZ_DIR="lib/openzeppelin-contracts"

if [ ! -f "$OZ_DIR/contracts/token/ERC20/ERC20.sol" ]; then
  rm -rf "$OZ_DIR"
  mkdir -p lib
  git clone --quiet --depth 1 --branch "$OZ_VERSION" \
    https://github.com/OpenZeppelin/openzeppelin-contracts.git "$OZ_DIR" 2>/dev/null
fi

forge build --quiet

mkdir -p out
node -e '
const fs = require("fs");
const art = JSON.parse(fs.readFileSync("forge-out/Token.sol/Token.json", "utf8"));
fs.writeFileSync("out/Token.json", JSON.stringify({ abi: art.abi, bytecode: art.bytecode.object }, null, 2));
'
