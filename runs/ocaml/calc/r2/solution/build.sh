#!/usr/bin/env bash
# Build an optimized native release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

flags="-O3 -unsafe -inline 200"
# -O3 is only meaningful with flambda; drop it otherwise.
if ! ocamlopt -config | grep '^flambda: true' >/dev/null; then
  flags="-unsafe -inline 200"
fi

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
cp calc.ml "$build_dir/"
# shellcheck disable=SC2086
ocamlopt $flags -o "$build_dir/app" "$build_dir/calc.ml"
mv "$build_dir/app" ./app
