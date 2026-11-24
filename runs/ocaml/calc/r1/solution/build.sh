#!/usr/bin/env bash
# Builds an optimized release binary at ./app using only the OCaml standard library.
set -euo pipefail
cd "$(dirname "$0")"
build_dir=_build
rm -rf "$build_dir"
mkdir -p "$build_dir"
cp src/calc.ml "$build_dir/"
(cd "$build_dir" && ocamlopt -unsafe -inline 200 -o calc calc.ml)
cp "$build_dir/calc" ./app
