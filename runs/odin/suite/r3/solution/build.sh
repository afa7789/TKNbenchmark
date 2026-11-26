#!/usr/bin/env bash
# Builds the optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
odin build . -out:app -o:speed -no-bounds-check -vet -strict-style
