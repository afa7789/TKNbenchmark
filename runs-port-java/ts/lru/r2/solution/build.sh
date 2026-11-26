#!/usr/bin/env bash
# Creates the ./app launcher, which runs the TypeScript sources directly on Node.js
# (Node strips the type annotations natively; no compilation step is needed).
set -euo pipefail
cd "$(dirname "$0")"


cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning --max-old-space-size=4096 "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app
