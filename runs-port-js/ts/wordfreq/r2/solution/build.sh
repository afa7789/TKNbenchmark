#!/usr/bin/env bash
# Builds ./app: a launcher that runs the TypeScript wordfreq program with
# Node.js, which executes .ts sources natively via type stripping.
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/wordfreq.ts" "$@"
LAUNCHER
chmod +x app
