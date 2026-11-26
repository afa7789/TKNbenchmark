#!/usr/bin/env bash
# Writes the ./app launcher. Node.js runs the TypeScript sources directly (type stripping),
# so there is no compile step; the launcher enables the on-disk compile cache for fast startup.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "build.sh: node not found" >&2; exit 1; }

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export NODE_COMPILE_CACHE="${NODE_COMPILE_CACHE:-$DIR/.cache/node-compile}"
exec node --disable-warning=ExperimentalWarning "$DIR/src/main.ts" "$@"
LAUNCHER
chmod +x app

# Warm the compile cache and smoke-test the result.
[[ "$(printf '1 + 2 * 3\n' | ./app)" == 7 ]] || { echo "build.sh: smoke test failed" >&2; exit 1; }
