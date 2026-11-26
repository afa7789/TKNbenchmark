#!/usr/bin/env bash
# Build kvhttp and install the ./app launcher.
# The server uses only the Node.js standard library and runs its TypeScript
# sources directly (Node's built-in type stripping), so there is nothing to
# fetch or compile at build time. `npm install && npm run typecheck` runs the
# full type checker during development.
set -euo pipefail
cd "$(dirname "$0")"

node -e 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 23 || (major === 23 && minor < 6)) { console.error(`kvhttp needs Node.js >= 23.6, found ${process.version}`); process.exit(1) }'
# Fail the build early on syntax errors.
node --check src/main.ts

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$HERE/src/main.ts" "$@"
LAUNCHER
chmod +x app
