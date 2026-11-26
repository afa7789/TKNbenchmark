#!/usr/bin/env bash
# Builds ./app: installs dev dependencies, type-checks and compiles src/ to dist/,
# then writes a launcher that runs the compiled server with Node.js.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "node is required" >&2; exit 1; }
command -v npm >/dev/null || { echo "npm is required" >&2; exit 1; }

if [[ -f package-lock.json ]]; then
  npm ci --no-audit --no-fund --loglevel=error
else
  npm install --no-audit --no-fund --loglevel=error
fi

rm -rf dist
npx --no-install tsc -p tsconfig.json

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export NODE_ENV=production
exec node "$DIR/dist/server.js" "$@"
LAUNCHER
chmod +x app
