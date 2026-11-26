#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'LAUNCHER'
#!/bin/sh
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app
