#!/usr/bin/env bash
# Installs dev tooling, type-checks the sources, and writes the ./app launcher.
# Node.js runs the TypeScript sources directly (type stripping), so there is no emit step.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f package-lock.json ]]; then
  npm ci --no-audit --no-fund --loglevel=error
else
  npm install --no-audit --no-fund --loglevel=error
fi
npx --no-install tsc --noEmit -p tsconfig.json

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --no-warnings --max-old-space-size=4096 "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app
