#!/usr/bin/env bash
# Install the ./app launcher, which runs the TypeScript sources directly on Node.js.
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --no-warnings --max-semi-space-size=64 "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app
