#!/usr/bin/env bash
# Builds ./app: a launcher that runs the TypeScript entry point with Node's native type stripping.
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/main.ts" "$@"
LAUNCHER
chmod +x app
