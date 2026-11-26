#!/usr/bin/env bash
# Builds ./app: type-checks and compiles src/ to dist/, then writes a node launcher.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f package-lock.json ]]; then
  npm ci --no-audit --no-fund --loglevel=error
else
  npm install --no-audit --no-fund --loglevel=error
fi

rm -rf dist
npx --no-install tsc -p .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node "$(dirname "$0")/dist/main.js" "$@"
LAUNCHER
chmod +x app
