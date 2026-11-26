#!/usr/bin/env bash
# Produces ./app, a launcher that runs the TypeScript entry point with Node's
# native type stripping.
set -euo pipefail
cd "$(dirname "$0")"

rm -f app
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec node --disable-warning=ExperimentalWarning "${dir}/src/wordfreq.ts" "$@"
LAUNCHER
chmod +x app
