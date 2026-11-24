#!/usr/bin/env bash
# Build an optimized native release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
cp main.ml "$build_dir/"
flags=(-unsafe -inline 200)
# -O3 is only accepted by flambda compilers; probe for it.
if ocamlopt -config | grep -q '^flambda: true'; then
  flags+=(-O3)
fi
ocamlopt "${flags[@]}" -o "$build_dir/app" "$build_dir/main.ml"
cp "$build_dir/app" ./app
