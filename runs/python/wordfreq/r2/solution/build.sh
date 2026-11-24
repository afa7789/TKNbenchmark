#!/usr/bin/env bash
# Build: byte-compile the program and install the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

python3 -m py_compile wordfreq.py

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec python3 -O "$(dirname "$0")/wordfreq.py" "$@"
LAUNCHER
chmod +x app
