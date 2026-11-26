#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript entry point with Node.js
# (which strips types natively, so no compile step is needed).
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "build.sh: node not found" >&2; exit 1; }
cat > app <<'LAUNCH'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --max-old-space-size=4096 "$dir/src/main.ts" "$@"
LAUNCH
chmod +x app

# Smoke test: the launcher must run the entry point cleanly.
[[ "$(printf 'b a B' | ./app)" == $'2 b\n1 a' ]] || { echo "build.sh: smoke test failed" >&2; exit 1; }
