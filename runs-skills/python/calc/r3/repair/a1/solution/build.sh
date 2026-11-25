#!/usr/bin/env bash
# Byte-compile the evaluator and install the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"
python3 -m py_compile calc.py
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec python3 -I "$(dirname "$0")/calc.py" "$@"
LAUNCHER
chmod +x app
