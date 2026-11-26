#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript sources with Node.js,
# which strips types natively (no compilation step needed).
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "node not found" >&2; exit 1; }

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app

# Smoke test.
[ "$(printf '1 + 2 * 3\n' | ./app)" = "7" ] || { echo "smoke test failed" >&2; exit 1; }
