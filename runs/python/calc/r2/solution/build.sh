#!/usr/bin/env bash
# Build: byte-compile the calculator module and generate the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

python3 -OO -m py_compile calc.py

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -OO -I -S -c 'import sys; sys.path.insert(0, sys.argv[1]); import calc; sys.exit(calc.main())' "$dir"
LAUNCHER
chmod +x app
