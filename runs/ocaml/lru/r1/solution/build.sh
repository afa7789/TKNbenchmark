#!/usr/bin/env bash
# Builds an optimized native binary at ./app using only ocamlopt.
set -euo pipefail
cd "$(dirname "$0")"
build_dir=_build
rm -rf "$build_dir"
mkdir -p "$build_dir"
cp src/lru.mli src/lru.ml src/main.ml "$build_dir"/
(
  cd "$build_dir"
  ocamlopt -inline 200 -unsafe -w +a-4-9-40-41-42-44-45-70 \
    lru.mli lru.ml main.ml -o app
)
mv "$build_dir/app" ./app
rm -rf "$build_dir"
