#!/usr/bin/env bash
# Builds an optimized release binary at ./app. Uses only Odin's core library.
set -euo pipefail
cd "$(dirname "$0")"
odin build src -out:app -o:speed -vet -strict-style
