#!/usr/bin/env bash
# Builds ./app: fetches the pinned toolchain, type-checks and compiles src/ to dist/,
# then writes a launcher that runs the compiled server with Node.js.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "build.sh: node is required" >&2; exit 1; }
command -v npm >/dev/null || { echo "build.sh: npm is required" >&2; exit 1; }

npm ci --no-audit --no-fund --loglevel=error
rm -rf dist
npx --no-install tsc -p tsconfig.json

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "$DIR/dist/main.js" "$@"
LAUNCHER
chmod +x app
