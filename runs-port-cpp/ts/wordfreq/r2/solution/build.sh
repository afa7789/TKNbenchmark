#!/usr/bin/env bash
# Produces ./app: a launcher that runs src/main.ts with Node's native TypeScript support.
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app
