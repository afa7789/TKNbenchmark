#!/usr/bin/env bash
# Builds the release launcher at ./app (Node.js runs the TypeScript source natively).
set -euo pipefail
cd "$(dirname "$0")"
node --check src/calc.ts
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/calc.ts" "$@"
LAUNCHER
chmod +x app build.sh
