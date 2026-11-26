#!/usr/bin/env bash
# Installs dependencies, compiles the TypeScript sources to dist/ and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

npm ci --no-audit --no-fund --loglevel=error
rm -rf dist
npx --no-install tsc -p tsconfig.json

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec node "$dir/dist/main.js" "$@"
LAUNCHER
chmod +x app
