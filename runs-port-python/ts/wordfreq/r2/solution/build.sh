#!/usr/bin/env bash
# Build: install the TypeScript sources and the ./app launcher.
# Node.js runs .ts files natively (type stripping), so no transpilation step is needed.
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/wordfreq.ts" "$@"
LAUNCHER
chmod +x app

# Smoke test: the program must load and run.
[ "$(printf 'a A b' | ./app)" = $'2 a\n1 b' ]
