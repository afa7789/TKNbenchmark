#!/usr/bin/env bash
# Install the ./app launcher, which runs the TypeScript source directly on Node.js.
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(printf "1\nSET a 1\nGET a\n" | node --no-warnings src/lru.ts)" == 1 ]]
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --no-warnings --max-semi-space-size=64 "$(dirname "$0")/src/lru.ts" "$@"
LAUNCHER
chmod +x app build.sh
