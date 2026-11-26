#!/usr/bin/env bash
# Installs a launcher at ./app that runs the TypeScript sources with Node.js,
# which executes .ts files natively (type stripping); no compilation step is needed.
set -euo pipefail
cd "$(dirname "$0")"

node --check src/main.ts

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$dir/src/main.ts" "$@"
LAUNCHER
chmod +x app
