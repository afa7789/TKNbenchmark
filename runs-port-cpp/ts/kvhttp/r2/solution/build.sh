#!/usr/bin/env bash
# Installs dev dependencies, type-checks the sources and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f package-lock.json ]]; then
  npm ci --no-audit --no-fund --loglevel=error
else
  npm install --no-audit --no-fund --loglevel=error
fi
npx --no-install tsc -p tsconfig.json

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app
