#!/usr/bin/env bash
# Compiles Vesting and writes out/Vesting.json with {"abi": [...], "bytecode": "0x..."}.
set -euo pipefail
cd "$(dirname "$0")"

FORGE_STD_VERSION=v1.17.0
if [ ! -f lib/forge-std/src/Test.sol ]; then
  rm -rf lib/forge-std
  git clone --quiet --depth 1 --branch "$FORGE_STD_VERSION" \
    https://github.com/foundry-rs/forge-std.git lib/forge-std
fi

forge build --skip test --skip script

mkdir -p out
jq '{abi: .abi, bytecode: .bytecode.object}' forge-out/Vesting.sol/Vesting.json > out/Vesting.json
