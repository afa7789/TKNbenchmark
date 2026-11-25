#!/usr/bin/env bash
# Produces ./app, a launcher that runs the program with Node.js.
set -euo pipefail
cd "$(dirname "$0")"
command -v node >/dev/null || { echo "node not found" >&2; exit 1; }
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node "$(dirname "$0")/src/main.js" "$@"
LAUNCHER
chmod +x app
