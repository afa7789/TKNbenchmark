#!/usr/bin/env bash
# Builds ./app: a launcher that runs the Julia implementation with release flags.
set -euo pipefail
cd "$(dirname "$0")"

command -v julia >/dev/null || { echo "julia not found on PATH" >&2; exit 1; }

cat > app <<'LAUNCH'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec julia --startup-file=no --history-file=no -O3 --check-bounds=no "$DIR/src/main.jl" "$@"
LAUNCH
chmod +x app

# Smoke test so a broken build fails here rather than at run time.
printf '4 1\n0 1\n1 3\n2 5\n3 7\n' | ./app >/dev/null
