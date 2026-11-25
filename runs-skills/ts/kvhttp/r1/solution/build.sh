#!/usr/bin/env bash
# Builds kvhttp: installs dev tooling, type-checks, and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

if [ -f package-lock.json ]; then
  npm ci --no-audit --no-fund --loglevel=error
else
  npm install --no-audit --no-fund --loglevel=error
fi
npx --no-install tsc -p tsconfig.json

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app
