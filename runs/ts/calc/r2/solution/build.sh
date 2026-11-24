#!/usr/bin/env bash
# Produces ./app: a launcher that runs the TypeScript sources with Node's
# native type stripping (no third-party build tools required).
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/bin/sh
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec node --disable-warning=ExperimentalWarning "$dir/src/main.ts" "$@"
LAUNCHER
chmod +x app
