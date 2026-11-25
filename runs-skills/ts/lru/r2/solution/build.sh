#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript sources natively with Node.
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'SH'
#!/usr/bin/env bash
exec node --max-old-space-size=4096 "$(dirname "$0")/src/main.ts"
SH
chmod +x app
