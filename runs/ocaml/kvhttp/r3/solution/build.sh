#!/usr/bin/env bash
# Builds the optimized release binary at ./app.
# Requires an OCaml (>= 5.1) toolchain and dune; no third-party packages.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v dune >/dev/null 2>&1; then
  if command -v opam >/dev/null 2>&1; then
    opam install -y dune
    eval "$(opam env)"
  else
    echo "build.sh: dune not found and opam unavailable" >&2
    exit 1
  fi
fi

dune build --profile release --root . ./bin/main.exe
install -m 755 _build/default/bin/main.exe ./app
