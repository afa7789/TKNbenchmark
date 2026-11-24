#!/usr/bin/env bash
# Build an optimized native binary at ./app using only the OCaml compiler.
set -euo pipefail
cd "$(dirname "$0")"
builddir=$(mktemp -d)
trap 'rm -rf "$builddir"' EXIT
cp main.ml "$builddir/"
ocamlopt -config | grep -q '^flambda: true' && opt=(-O3) || opt=()
ocamlopt "${opt[@]+"${opt[@]}"}" -unsafe -inline 200 -o "$builddir/app" "$builddir/main.ml"
cp "$builddir/app" ./app
