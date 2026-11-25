#!/usr/bin/env bash
# Node runs the TypeScript sources directly; the build writes the launcher.
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'LAUNCHER'
#!/bin/sh
exec node "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app
