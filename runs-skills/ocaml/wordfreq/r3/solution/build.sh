#!/usr/bin/env bash
# Build an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
dune build --release ./bin/main.exe
install -m 755 _build/default/bin/main.exe ./app
