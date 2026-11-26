#!/usr/bin/env bash
# Produces ./app: a launcher that runs the LRU simulator with Node.js,
# which executes TypeScript natively via type stripping.
set -euo pipefail
cd "$(dirname "$0")"
node --check src/lru.ts
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/lru.ts" "$@"
LAUNCHER
chmod +x app
