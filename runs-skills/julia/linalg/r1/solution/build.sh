#!/usr/bin/env bash
# Builds ./app: a launcher that runs the Julia implementation in src/linalg.jl.
set -euo pipefail
cd "$(dirname "$0")"

command -v julia >/dev/null || { echo "julia not found on PATH" >&2; exit 1; }

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec julia --startup-file=no --history-file=no -O2 "$DIR/src/linalg.jl" "$@"
LAUNCHER
chmod +x app

# Warm up: ensures LinearAlgebra's precompiled image is present and the script runs.
printf '1\n4\n2\n' | ./app >/dev/null
