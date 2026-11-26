#!/usr/bin/env bash
# Installs the ./app launcher. Node.js runs the TypeScript sources directly
# (type stripping), so there is no separate compile step.
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app
