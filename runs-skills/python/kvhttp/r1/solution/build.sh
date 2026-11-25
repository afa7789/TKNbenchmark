#!/usr/bin/env bash
# Builds ./app: byte-compiles the package (optimized) and installs the launcher.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

python3 - <<'PY'
import sys
if sys.version_info < (3, 12):
    sys.exit(f"python3 >= 3.12 required, found {sys.version.split()[0]}")
PY

python3 -O -m compileall -q kvhttp
install -m 0755 app.in app
