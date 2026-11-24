#!/usr/bin/env bash
# Builds ./app: a launcher that runs the wordfreq program with Node.js.
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node "$(dirname "$0")/src/wordfreq.js" "$@"
LAUNCHER
chmod +x app
