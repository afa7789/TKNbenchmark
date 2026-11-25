#!/usr/bin/env bash
# Builds ./app: checks the toolchain, compiles the server and writes a launcher.
# No third-party dependencies; only the standard library is used.
set -euo pipefail
cd "$(dirname "$0")"

python3 -c 'import sys; sys.exit(sys.version_info < (3, 12))' \
  || { echo "python3 >= 3.12 required" >&2; exit 1; }
python3 -O -m py_compile kvhttp.py

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -O -P "$dir/kvhttp.py" "$@"
LAUNCHER
chmod +x app
