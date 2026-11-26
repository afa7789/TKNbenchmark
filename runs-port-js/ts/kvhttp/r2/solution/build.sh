#!/usr/bin/env bash
# Builds ./app: a launcher that runs the TypeScript server directly with Node.js
# (native type stripping; no runtime dependencies).
set -euo pipefail
cd "$(dirname "$0")"
command -v node >/dev/null || { echo "node is required" >&2; exit 1; }
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/server.ts" "$@"
LAUNCHER
chmod +x app
