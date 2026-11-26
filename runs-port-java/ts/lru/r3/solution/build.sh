#!/usr/bin/env bash
# Creates the ./app launcher, which runs the TypeScript sources directly on Node.js
# (Node strips types natively, so there is no separate compile step).
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app
