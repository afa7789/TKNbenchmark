#!/usr/bin/env bash
# Builds Token and writes out/Token.json ({abi, bytecode}).
set -euo pipefail
cd "$(dirname "$0")"

OZ_VERSION="v5.7.0"
OZ_DIR="lib/openzeppelin-contracts"

if [ ! -f "$OZ_DIR/contracts/token/ERC20/ERC20.sol" ]; then
  rm -rf "$OZ_DIR"
  mkdir -p lib
  git clone --quiet --depth 1 --branch "$OZ_VERSION" \
    https://github.com/OpenZeppelin/openzeppelin-contracts.git "$OZ_DIR"
fi

forge build --skip test --skip script

mkdir -p out
jq '{abi: .abi, bytecode: .bytecode.object}' forge-out/Token.sol/Token.json > out/Token.json
