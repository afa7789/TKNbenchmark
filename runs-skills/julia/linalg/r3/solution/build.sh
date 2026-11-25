#!/usr/bin/env bash
# Builds ./app: a launcher that runs the Julia program in src/ with optimizations enabled.
set -euo pipefail
cd "$(dirname "$0")"

command -v julia >/dev/null || { echo "julia not found on PATH" >&2; exit 1; }

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec julia --startup-file=no --history-file=no -O3 "$DIR/src/main.jl" "$@"
LAUNCHER
chmod +x app

# Smoke test so a broken build fails here rather than in the tests.
printf '1\n4\n2\n' | ./app >/dev/null
