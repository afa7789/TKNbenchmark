#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript entry point with Node,
# which executes .ts sources natively (type stripping, no transpile step).
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "build.sh: node not found" >&2; exit 1; }

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --no-warnings --max-old-space-size=4096 "$here/src/main.ts" "$@"
LAUNCHER
chmod +x app
