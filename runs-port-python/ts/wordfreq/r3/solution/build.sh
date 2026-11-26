#!/usr/bin/env bash
# Build the wordfreq launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

# Smoke-test that Node can load and run the TypeScript source.
printf 'ok' | node src/wordfreq.ts >/dev/null

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/wordfreq.ts" "$@"
LAUNCHER
chmod +x app
