#!/usr/bin/env bash
# Builds an optimized native binary at ./app using only the OCaml compiler.
set -euo pipefail
cd "$(dirname "$0")"

build_dir=_build
rm -rf "$build_dir"
mkdir -p "$build_dir"
cp src/lru.mli src/lru.ml src/main.ml "$build_dir"/

(
  cd "$build_dir"
  flags=(-unsafe -inline 200)
  if ocamlopt -config | grep -q '^flambda: true'; then
    flags+=(-O3)
  fi
  ocamlopt "${flags[@]}" -o app lru.mli lru.ml main.ml
)

mv "$build_dir/app" ./app
