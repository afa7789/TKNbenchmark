#!/usr/bin/env bash
# Build: byte-compile the package (optimized) and make the launcher executable.
set -euo pipefail
cd "$(dirname "$0")"
python3 -O -m compileall -q lru
chmod +x app
