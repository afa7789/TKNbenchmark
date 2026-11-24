#!/usr/bin/env bash
# Builds the optimized release binary at ./app.
# Needs only the OCaml distribution (unix, threads) plus dune; dune is
# fetched through opam if it is not already installed.
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v dune >/dev/null 2>&1; then
  opam install -y dune
  eval "$(opam env)"
fi
dune build --profile release ./bin/main.exe
install -m 755 _build/default/bin/main.exe ./app
