#!/usr/bin/env bash
# Builds an optimized release binary at ./app. No third-party dependencies.
set -euo pipefail
cd "$(dirname "$0")"
odin build src -o:speed -out:app
