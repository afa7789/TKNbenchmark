#!/usr/bin/env bash
# Produces ./app: a launcher that runs the Node.js entry point.
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node "$(dirname "$0")/src/index.js" "$@"
LAUNCHER
chmod +x app
