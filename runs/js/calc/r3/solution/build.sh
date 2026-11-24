#!/usr/bin/env bash
# Produces ./app: a launcher that runs the calculator with Node.js.
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'LAUNCHER'
#!/bin/sh
exec node "$(dirname "$0")/src/calc.js" "$@"
LAUNCHER
chmod +x app
