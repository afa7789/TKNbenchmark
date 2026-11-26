#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript sources with Node's
# native type stripping. No runtime dependencies are required.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "node is required" >&2; exit 1; }

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app
