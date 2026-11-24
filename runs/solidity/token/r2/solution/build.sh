#!/usr/bin/env bash
# Compiles Token and writes out/Token.json ({abi, bytecode}). Fetches pinned dependencies on first run.
set -euo pipefail
cd "$(dirname "$0")"

fetch() { # <dir> <repo-url> <tag>
  if [ ! -d "$1/.git" ]; then
    rm -rf "$1"
    mkdir -p "$(dirname "$1")"
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$3" "$2" "$1"
  fi
}

fetch lib/openzeppelin-contracts https://github.com/OpenZeppelin/openzeppelin-contracts.git v5.1.0
fetch lib/forge-std https://github.com/foundry-rs/forge-std.git v1.9.4

forge build --quiet

mkdir -p out
node -e '
const fs = require("fs");
const art = JSON.parse(fs.readFileSync("forge-out/Token.sol/Token.json", "utf8"));
fs.writeFileSync("out/Token.json", JSON.stringify({ abi: art.abi, bytecode: art.bytecode.object }, null, 2) + "\n");
'
