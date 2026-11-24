#!/usr/bin/env bash
# Builds the Token contract and writes out/Token.json ({abi, bytecode}).
set -euo pipefail
cd "$(dirname "$0")"

# fetch_dep <dir> <git-url> <tag>: shallow-clone a pinned dependency if missing.
fetch_dep() {
  local dir="lib/$1" url="$2" tag="$3"
  if [ ! -d "$dir/.git" ]; then
    rm -rf "$dir"
    mkdir -p lib
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" "$url" "$dir"
  fi
}

fetch_dep openzeppelin-contracts https://github.com/OpenZeppelin/openzeppelin-contracts.git v5.1.0
# Test-only dependency; pass WITH_TESTS=1 to fetch it and run `forge test` afterwards.
if [ "${WITH_TESTS:-0}" = "1" ]; then
  fetch_dep forge-std https://github.com/foundry-rs/forge-std.git v1.9.4
fi

forge build --quiet --skip test

mkdir -p out
node -e '
const fs = require("fs");
const art = JSON.parse(fs.readFileSync("forge-out/Token.sol/Token.json", "utf8"));
fs.writeFileSync("out/Token.json", JSON.stringify({ abi: art.abi, bytecode: art.bytecode.object }, null, 2) + "\n");
'
