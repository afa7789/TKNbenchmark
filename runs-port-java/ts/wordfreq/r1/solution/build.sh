#!/usr/bin/env bash
# Installs a launcher at ./app that runs the TypeScript sources with Node.js,
# which strips type annotations natively (no compile step required).
set -euo pipefail
cd "$(dirname "$0")"

node --check src/main.ts

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app
