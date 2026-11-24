#!/usr/bin/env bash
# Build an optimized native release binary at ./app using only the OCaml compiler.
set -euo pipefail
cd "$(dirname "$0")"

build_dir=_build
rm -rf "$build_dir"
mkdir -p "$build_dir"
cp src/calc.ml src/main.ml "$build_dir"/

(
  cd "$build_dir"
  flags=(-O3 -inline 200)
  # -O3 is only accepted by flambda compilers; fall back gracefully.
  if ! ocamlopt -config | grep -q '^flambda: true'; then
    flags=(-inline 200)
  fi
  ocamlopt "${flags[@]}" -w +a-4-9-40-41-42-44-45-70 calc.ml main.ml -o app
)

cp "$build_dir/app" ./app
