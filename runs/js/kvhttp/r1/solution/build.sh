#!/usr/bin/env bash
# Builds ./app: a launcher that runs the server with Node.js. No third-party deps.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "node is required" >&2; exit 1; }
node --check src/server.js

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "$DIR/src/server.js" "$@"
LAUNCHER
chmod +x app
