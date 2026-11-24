#!/usr/bin/env bash
# Build the wordfreq launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

python3 -m py_compile wordfreq.py

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec python3 -O "$(dirname "$0")/wordfreq.py" "$@"
LAUNCHER
chmod +x app
