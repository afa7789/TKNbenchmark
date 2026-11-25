#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
odin build . -o:speed -out:app
