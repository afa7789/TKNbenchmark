#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
dune build --profile release --root . ./bin/main.exe
cp -f _build/default/bin/main.exe ./app
chmod +x ./app
