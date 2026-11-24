#!/usr/bin/env bash
# Build an optimized native binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

flags=(-unsafe -inline 200)
if ocamlopt -config | grep -q '^flambda: true'; then
  flags+=(-O3)
fi

build_dir=_build
rm -rf "$build_dir"
mkdir -p "$build_dir"
cp wordfreq.ml "$build_dir/"
(cd "$build_dir" && ocamlopt "${flags[@]}" -o app wordfreq.ml)
cp "$build_dir/app" ./app
