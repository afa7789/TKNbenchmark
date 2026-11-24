#!/usr/bin/env bash
# Build the release launcher at ./app (byte-compiles the module ahead of time).
set -euo pipefail
cd "$(dirname "$0")"

python3 -O -m py_compile wordfreq.py

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec python3 -O "$(dirname "$0")/wordfreq.py" "$@"
LAUNCHER
chmod +x app
