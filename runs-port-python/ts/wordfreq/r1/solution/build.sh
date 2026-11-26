#!/usr/bin/env bash
# Build the release launcher at ./app. Node.js runs the TypeScript source
# directly (type stripping), so the build writes a launcher script and
# smoke-tests it.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "build.sh: node not found" >&2; exit 1; }
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --no-warnings "$(dirname "$0")/src/wordfreq.ts" "$@"
LAUNCHER
chmod +x app

# Smoke test: the program must load and handle empty input.
./app </dev/null >/dev/null
