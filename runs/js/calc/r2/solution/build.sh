#!/usr/bin/env bash
# Produces ./app: a launcher that runs the calculator with Node.js.
set -euo pipefail
cd "$(dirname "$0")"

node --check src/evaluate.js
node --check src/main.js

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node "$(dirname "$0")/src/main.js" "$@"
LAUNCHER
chmod +x app
