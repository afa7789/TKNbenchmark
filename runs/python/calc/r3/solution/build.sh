#!/usr/bin/env bash
# Build the calc release: byte-compile with optimizations and install ./app.
set -euo pipefail
cd "$(dirname "$0")"

python3 -OO -m py_compile calc.py

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec python3 -OO "$(dirname "$0")/calc.py" "$@"
LAUNCHER
chmod +x app
