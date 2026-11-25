#!/usr/bin/env bash
# Build the release launcher at ./app (stdlib only; no packages to fetch).
set -euo pipefail
cd "$(dirname "$0")"

python3 -c 'import sys; sys.exit(sys.version_info < (3, 12))' \
  || { echo "python3 >= 3.12 required" >&2; exit 1; }

# Precompile optimized bytecode so startup is fast.
python3 -O -m compileall -q kvhttp

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHONPATH="$here${PYTHONPATH:+:$PYTHONPATH}" exec python3 -O -m kvhttp "$@"
LAUNCHER
chmod +x app
