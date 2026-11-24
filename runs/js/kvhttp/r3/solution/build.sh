#!/usr/bin/env bash
# Builds ./app: a launcher that runs the server with Node.js.
# The server has no third-party dependencies, so nothing needs fetching.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "build.sh: node is required" >&2; exit 1; }
node --check src/server.js
node --check src/main.js

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "$DIR/src/main.js" "$@"
LAUNCHER
chmod +x app
