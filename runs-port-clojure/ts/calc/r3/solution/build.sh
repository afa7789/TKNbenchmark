#!/usr/bin/env bash
# Builds the ./app launcher. Node.js runs the TypeScript sources directly
# (type stripping), so the "build" validates the toolchain and writes the launcher.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "node not found" >&2; exit 1; }

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$dir/src/main.ts" "$@"
LAUNCHER
chmod +x app

# Smoke test so a broken build fails here rather than at run time.
[[ "$(printf '1+2*3\n' | ./app)" == "7" ]]
