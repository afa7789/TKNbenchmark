#!/usr/bin/env bash
# Build the release launcher at ./app (byte-compiles calc.py for fast startup).
set -euo pipefail
cd "$(dirname "$0")"
python3 -O -m py_compile calc.py
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec python3 -O "$(dirname "$0")/calc.py" "$@"
LAUNCHER
chmod +x app
