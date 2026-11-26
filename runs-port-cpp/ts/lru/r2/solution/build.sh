#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript sources directly on Node.js
# (which strips types natively), so there is no separate compile step.
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --no-warnings --max-semi-space-size=64 "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app

# Smoke test: fails the build if the sources do not load.
printf '1\nSIZE\n' | ./app > /dev/null
