#!/usr/bin/env bash
# Produces ./app: a launcher that runs the LRU simulator with Node.js,
# which executes the TypeScript sources natively (type stripping).
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app
