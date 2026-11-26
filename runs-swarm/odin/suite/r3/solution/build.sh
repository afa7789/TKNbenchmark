#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

odin build src -out:app -o:speed -vet -strict-style
