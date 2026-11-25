#!/usr/bin/env bash
# Produces ./app, a launcher that runs the Julia implementation in src/linreg.jl.
set -euo pipefail
cd "$(dirname "$0")"
command -v julia >/dev/null || { echo "julia not found on PATH" >&2; exit 1; }
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec julia --startup-file=no --history-file=no -O3 "$DIR/src/linreg.jl" "$@"
LAUNCHER
chmod +x app
