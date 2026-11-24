#!/usr/bin/env bash
# Builds ./app: a launcher for the kvhttp package (stdlib only, no dependencies).
set -euo pipefail
cd "$(dirname "$0")"

python3 -m compileall -q -o 2 kvhttp

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec env PYTHONPATH="$DIR${PYTHONPATH:+:$PYTHONPATH}" python3 -OO -m kvhttp "$@"
LAUNCHER
chmod +x app
