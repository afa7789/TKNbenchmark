#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript sources directly on Node.
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'LAUNCH'
#!/usr/bin/env bash
exec node --no-warnings --max-semi-space-size=64 "$(dirname "$0")/src/main.ts" "$@"
LAUNCH
chmod +x app
