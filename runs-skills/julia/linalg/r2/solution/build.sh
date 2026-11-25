#!/usr/bin/env bash
# Produces ./app: a launcher that runs the Julia program with release settings.
set -euo pipefail
cd "$(dirname "$0")"
command -v julia >/dev/null || { echo "julia not found on PATH" >&2; exit 1; }
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec julia --startup-file=no --history-file=no -O2 "$DIR/src/main.jl" "$@"
LAUNCHER
chmod +x app
# Warm-up run to verify the program loads and runs.
printf '1\n4\n2\n' | ./app >/dev/null
