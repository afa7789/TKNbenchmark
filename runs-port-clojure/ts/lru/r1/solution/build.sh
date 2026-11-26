#!/usr/bin/env bash
# Produces the ./app launcher. Node runs the TypeScript sources natively,
# so there is no compile step; this just validates the toolchain.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "node not found" >&2; exit 1; }

cat > app <<'LAUNCH'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$DIR/src/main.ts" "$@"
LAUNCH
chmod +x app
