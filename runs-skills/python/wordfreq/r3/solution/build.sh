#!/usr/bin/env bash
# Build the release launcher at ./app (byte-compiles the module for fast startup).
set -euo pipefail
cd "$(dirname "$0")"

python3 -OO -m py_compile wordfreq.py

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec python3 -OO "$(dirname "$0")/wordfreq.py" "$@"
LAUNCHER
chmod +x app
