#!/usr/bin/env bash
# Builds the optimized release binary ./app from the packages under src/.
set -euo pipefail

cd "$(dirname "$0")"

odin build src -out:app -o:speed -vet -strict-style
