#!/usr/bin/env bash
# Produces ./app: a launcher that runs the program with Node.js.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "node not found" >&2; exit 1; }
node --check src/index.js
node --check src/wordfreq.js

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --max-old-space-size=4096 "$(dirname "$0")/src/index.js" "$@"
LAUNCHER
chmod +x app
