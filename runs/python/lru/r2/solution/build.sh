#!/usr/bin/env bash
# Byte-compile the module and install the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"
python3 -O -m py_compile lru.py
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec python3 -O "$(dirname "$0")/lru.py" "$@"
LAUNCHER
chmod +x app
