#!/usr/bin/env bash
# Builds the release artifact: compiles src/ to dist/ and installs the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f package-lock.json ]]; then
  npm ci --no-audit --no-fund --loglevel=error
else
  npm install --no-audit --no-fund --loglevel=error
fi

rm -rf dist
npx --no-install tsc -p tsconfig.json

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node "$(dirname "$0")/dist/main.js" "$@"
LAUNCHER
chmod +x app
