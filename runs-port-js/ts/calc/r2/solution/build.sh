#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript calculator with Node.js
# (Node strips the type annotations natively; no compile step is required).
set -euo pipefail
cd "$(dirname "$0")"

node --check src/evaluate.ts
node --check src/main.ts

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app
