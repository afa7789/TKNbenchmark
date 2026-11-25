#!/usr/bin/env bash
# Builds ./app: a launcher that runs the server with the local Node.js runtime.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "node is required" >&2; exit 1; }

# No runtime dependencies; install would be a no-op, but keep the step for future deps.
if [[ -f package-lock.json ]]; then npm ci --omit=dev --no-audit --no-fund; fi

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node "$(dirname "$0")/src/index.js" "$@"
LAUNCHER
chmod +x app
