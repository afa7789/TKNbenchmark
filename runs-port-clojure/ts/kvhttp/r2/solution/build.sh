#!/usr/bin/env bash
# Installs dependencies, compiles src/ to dist/, and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f package-lock.json ]]; then
  npm ci --no-audit --no-fund --loglevel=error
else
  npm install --no-audit --no-fund --loglevel=error
fi

rm -rf dist
npx --no-install tsc -p tsconfig.json

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
export NODE_ENV=production
exec node "$DIR/dist/main.js" "$@"
LAUNCHER
chmod +x app
