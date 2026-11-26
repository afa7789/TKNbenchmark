#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript source with Node.js
# (Node runs .ts files natively via type stripping, so no compile step is needed).
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'LAUNCHER'
#!/bin/sh
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/calc.ts" "$@"
LAUNCHER
chmod +x app
