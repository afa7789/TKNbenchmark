#!/usr/bin/env bash
# Builds an optimized release binary at ./app. Only the OCaml compiler,
# dune and the libraries distributed with OCaml (unix, threads) are needed.
set -euo pipefail
cd "$(dirname "$0")"
dune build --profile release ./bin/main.exe
cp -f _build/default/bin/main.exe ./app
chmod +x ./app
