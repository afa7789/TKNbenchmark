#!/usr/bin/env bash
# Builds ./app: a launcher that runs the server with the installed Node.js.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "node is required" >&2; exit 1; }

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node "$(dirname "$0")/src/index.js" "$@"
LAUNCHER
chmod +x app
