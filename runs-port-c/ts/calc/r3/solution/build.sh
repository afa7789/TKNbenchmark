#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript sources with Node.js,
# which executes .ts files natively (type stripping).
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "build.sh: node not found" >&2; exit 1; }

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app
