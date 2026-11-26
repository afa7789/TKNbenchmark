#!/usr/bin/env bash
# Produces ./app, a launcher that runs the TypeScript sources with Node's native type stripping.
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCH'
#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
exec node --no-warnings --max-old-space-size=4096 "$here/src/main.ts" "$@"
LAUNCH
chmod +x app
