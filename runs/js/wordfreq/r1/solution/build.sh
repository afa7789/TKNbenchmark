#!/usr/bin/env bash
# Produce ./app: a launcher that runs the wordfreq program with Node.js.
set -euo pipefail
cd "$(dirname "$0")"
node --check src/wordfreq.js
cat > app <<'LAUNCHER'
#!/bin/sh
exec node "$(dirname "$0")/src/wordfreq.js" "$@"
LAUNCHER
chmod +x app
