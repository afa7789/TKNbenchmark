#!/usr/bin/env bash
# Build an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
dune build --profile release ./bin/main.exe
cp -f _build/default/bin/main.exe ./app
chmod u+w ./app
