#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
odin build src -out:app -o:speed -no-bounds-check -disable-assert
