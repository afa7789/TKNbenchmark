#!/usr/bin/env bash
# Build kvhttp: byte-compile the package and install the ./app launcher.
# Uses only the Python standard library, so there is nothing to fetch.
set -euo pipefail
cd "$(dirname "$0")"

python3 -m compileall -q -o 2 kvhttp

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
export PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}"
exec python3 -OO -m kvhttp "$@"
LAUNCHER
chmod +x app
