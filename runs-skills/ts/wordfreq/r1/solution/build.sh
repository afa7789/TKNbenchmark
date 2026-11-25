#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript sources with Node (which strips types natively).
set -euo pipefail
cd "$(dirname "$0")"

# Type-check when a TypeScript compiler is available; Node itself never type-checks.
if command -v tsc >/dev/null 2>&1; then
  tsc -p tsconfig.json
fi

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app
