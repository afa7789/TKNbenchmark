#!/usr/bin/env bash
# Build: verify the TypeScript sources load, then generate the ./app launcher.
# Node runs .ts natively (type stripping), so no transpile step is needed.
set -euo pipefail
cd "$(dirname "$0")"

node --check src/main.ts
node --check src/calc.ts

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$dir/src/main.ts"
LAUNCHER
chmod +x app
