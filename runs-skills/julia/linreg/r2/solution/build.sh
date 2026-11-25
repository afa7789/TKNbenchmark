#!/usr/bin/env bash
# Builds ./app: a launcher that runs the LinReg Julia program.
set -euo pipefail
cd "$(dirname "$0")"

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec julia --startup-file=no --history-file=no -O3 "$DIR/src/LinReg.jl" "$@"
LAUNCHER
chmod +x app

# Sanity check that the program loads and runs.
printf '3 1\n0 1\n1 2\n2 3.5\n' | ./app > /dev/null
