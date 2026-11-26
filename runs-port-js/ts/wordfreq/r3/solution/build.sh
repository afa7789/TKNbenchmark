#!/usr/bin/env bash
# Builds ./app: a launcher that runs the wordfreq TypeScript program with Node.js
# (Node runs .ts files natively via type stripping; no compile step is needed).
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/wordfreq.ts" "$@"
LAUNCHER
chmod +x app
