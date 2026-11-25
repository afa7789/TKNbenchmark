#!/usr/bin/env bash
# Builds ./app: a launcher that runs the calculator with Node.js.
set -euo pipefail
cd "$(dirname "$0")"
command -v node >/dev/null || { echo "node not found" >&2; exit 1; }
node --check src/calc.js
node --check src/main.js
chmod +x app
