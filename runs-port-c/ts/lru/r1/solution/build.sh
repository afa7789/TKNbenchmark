#!/usr/bin/env bash
# Build ./app: a launcher that runs the TypeScript sources with Node.js,
# which executes .ts files natively via type stripping.
set -euo pipefail
cd "$(dirname "$0")"

node --check src/main.ts

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --no-warnings --max-old-space-size=4096 "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app
