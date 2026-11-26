#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript calculator with Node.js
# (which executes .ts sources natively via type stripping).
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'LAUNCHER'
#!/bin/sh
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/calc.ts" "$@"
LAUNCHER
chmod +x app
