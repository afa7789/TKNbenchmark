#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript entry point with Node,
# which strips types natively (no compile step required).
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --no-warnings --max-old-space-size=4096 "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app
