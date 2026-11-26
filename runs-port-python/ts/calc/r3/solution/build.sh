#!/usr/bin/env bash
# Build the calc release: install the ./app launcher and smoke-test it.
# Node.js runs the TypeScript source directly (type stripping), so there is
# no separate compile step.
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/calc.ts" "$@"
LAUNCHER
chmod +x app

if [[ "$(printf '1 + 2 * 3\n' | ./app)" != "7" ]]; then
  echo "build.sh: smoke test failed" >&2
  exit 1
fi
