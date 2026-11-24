#!/usr/bin/env bash
# Produces ./app: a launcher that runs the LRU simulator with Node.js.
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node "$(dirname "$0")/src/main.js" "$@"
LAUNCHER
chmod +x app
