#!/usr/bin/env bash
# Builds ./app: a launcher for the stdlib-only kvhttp server.
set -euo pipefail
cd "$(dirname "$0")"

python3 -m py_compile kvhttp.py

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec python3 -O "$(dirname "$0")/kvhttp.py" "$@"
LAUNCHER
chmod +x app
