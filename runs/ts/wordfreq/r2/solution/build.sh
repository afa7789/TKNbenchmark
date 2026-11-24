#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript entry point with Node's
# native type stripping (no compile step or third-party tooling required).
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/bin/sh
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app
