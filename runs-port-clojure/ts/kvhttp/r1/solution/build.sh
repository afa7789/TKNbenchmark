#!/usr/bin/env bash
# Installs dev tooling, type-checks and tests the sources, and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

npm ci --no-audit --no-fund --loglevel=error
npx --no-install tsc
node --test test/

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec node "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app
