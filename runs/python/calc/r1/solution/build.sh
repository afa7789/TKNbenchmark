#!/usr/bin/env bash
# Builds the release launcher at ./app (byte-compiles the module with optimizations).
set -euo pipefail
cd "$(dirname "$0")"
python3 -O -m py_compile calc.py
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec python3 -O "$(dirname "$0")/calc.py" "$@"
LAUNCHER
chmod +x app
