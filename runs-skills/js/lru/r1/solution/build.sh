#!/usr/bin/env bash
# Produces ./app, a launcher that runs the Node.js implementation.
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'SH'
#!/bin/sh
exec node "$(dirname "$0")/src/main.js" "$@"
SH
chmod +x app
