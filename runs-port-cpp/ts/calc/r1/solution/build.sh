#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'SH'
#!/usr/bin/env bash
exec node --disable-warning=ExperimentalWarning "$(dirname "$0")/src/main.ts" "$@"
SH
chmod +x app
