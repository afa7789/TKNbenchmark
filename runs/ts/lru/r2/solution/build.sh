#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript sources with Node.js,
# which strips types natively (no compilation step required).
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --no-warnings --max-old-space-size=4096 "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app
