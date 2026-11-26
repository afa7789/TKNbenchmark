#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript sources with Node's
# native type stripping (standard library only, no build tooling required).
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning --max-semi-space-size=64 "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app

# Smoke test: fail the build if the sources do not load and run correctly.
if [[ "$(printf '1\nSET a 1\nGET a\n' | ./app)" != "1" ]]; then
  echo "build.sh: smoke test failed" >&2
  exit 1
fi
