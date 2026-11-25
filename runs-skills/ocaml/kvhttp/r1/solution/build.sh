#!/usr/bin/env bash
# Builds the optimized release binary at ./app.
# Dependencies: only the compiler-distributed `unix` and `threads` libraries,
# so no opam packages need to be fetched.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v dune >/dev/null 2>&1; then
  if command -v opam >/dev/null 2>&1; then
    eval "$(opam env 2>/dev/null || true)"
    command -v dune >/dev/null 2>&1 || opam install -y dune
    eval "$(opam env)"
  else
    echo "build.sh: dune (or opam) is required" >&2
    exit 1
  fi
fi

dune build --profile release ./bin/main.exe
install -m 755 _build/default/bin/main.exe ./app
