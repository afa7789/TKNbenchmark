#!/usr/bin/env bash
# Builds ./app: installs dev tooling, type-checks the sources, and writes the launcher.
set -euo pipefail
cd "$(dirname "$0")"

npm install --no-audit --no-fund --loglevel=error
npx --no-install tsc -p tsconfig.json

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app
