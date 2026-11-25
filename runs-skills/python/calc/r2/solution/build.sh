#!/usr/bin/env bash
# Build ./app: syntax-check calc.py and install a small python3 launcher.
set -euo pipefail
cd "$(dirname "$0")"
python3 -O -m py_compile calc.py
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec python3 -I -O "$(dirname "$0")/calc.py" "$@"
LAUNCHER
chmod +x app
