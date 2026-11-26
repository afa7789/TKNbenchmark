#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
odin build src -out:app -o:speed -no-bounds-check -disable-assert -vet -strict-style
