#!/usr/bin/env bash
# Builds ./app: a launcher that runs the TypeScript sources with Node's native
# type stripping (no runtime dependencies). Type-checking is available via
# `npm install && npm run typecheck` but is not required to build.
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app
