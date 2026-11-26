#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript sources with Node.js.
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec node --no-warnings "$dir/src/lru.ts" "$@"
LAUNCHER
chmod +x app
