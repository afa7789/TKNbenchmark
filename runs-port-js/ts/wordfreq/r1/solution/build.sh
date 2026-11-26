#!/usr/bin/env bash
# Produce ./app: a launcher that runs the wordfreq TypeScript program with Node.js
# (which executes .ts files natively via type stripping).
set -euo pipefail
cd "$(dirname "$0")"
# Smoke-run the program so syntax/type-stripping errors fail the build.
printf "" | node src/wordfreq.ts >/dev/null
cat > app <<'LAUNCHER'
#!/bin/sh
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/wordfreq.ts" "$@"
LAUNCHER
chmod +x app
