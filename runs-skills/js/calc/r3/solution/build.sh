#!/usr/bin/env bash
# Produces ./app, a launcher that runs the evaluator with Node.js.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "node not found" >&2; exit 1; }
node --check src/calc.js
node --check src/main.js

cat > app <<'SH'
#!/bin/sh
exec node "$(dirname "$0")/src/main.js" "$@"
SH
chmod +x app
