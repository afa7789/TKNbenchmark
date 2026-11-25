#!/usr/bin/env bash
# Builds ./app: a launcher that runs the byte-compiled LRU simulator.
set -euo pipefail
cd "$(dirname "$0")"
python3 -O -m py_compile src/lru.py
cat > app <<'LAUNCH'
#!/usr/bin/env bash
exec python3 -O "$(dirname "$0")/src/lru.py" "$@"
LAUNCH
chmod +x app
