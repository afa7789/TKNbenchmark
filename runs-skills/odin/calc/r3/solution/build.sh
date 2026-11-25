#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
odin build src -o:speed -out:app
