#!/usr/bin/env bash
# Builds an optimized release binary at ./app. Uses only the Odin core library.
set -euo pipefail
cd "$(dirname "$0")"
odin build src -o:speed -out:app
