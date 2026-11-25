#!/usr/bin/env bash
# Builds ./app: a launcher that runs the server with the installed Node.js.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "node is required" >&2; exit 1; }
# No runtime dependencies; install only if some are ever added.
if grep -q '"dependencies"' package.json; then
  npm ci --omit=dev --no-audit --no-fund
fi

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "$dir/src/index.js" "$@"
LAUNCHER
chmod +x app
