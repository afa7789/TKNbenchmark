#!/usr/bin/env bash
# Compiles Token and writes out/Token.json ({"abi": [...], "bytecode": "0x..."}).
set -euo pipefail
cd "$(dirname "$0")"

OZ_VERSION="v5.7.0"
FORGE_STD_VERSION="v1.17.0"

# Fetch a pinned dependency tag into lib/ unless it is already present.
fetch() { # <github-repo> <tag> <dest>
    if [ ! -d "$3" ]; then
        git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$2" \
            "https://github.com/$1.git" "$3"
    fi
}

fetch OpenZeppelin/openzeppelin-contracts "$OZ_VERSION" lib/openzeppelin-contracts
fetch foundry-rs/forge-std "$FORGE_STD_VERSION" lib/forge-std

forge build src

mkdir -p out
node -e '
const fs = require("fs");
const a = JSON.parse(fs.readFileSync("forge-out/Token.sol/Token.json", "utf8"));
fs.writeFileSync("out/Token.json", JSON.stringify({ abi: a.abi, bytecode: a.bytecode.object }, null, 2) + "\n");
'
