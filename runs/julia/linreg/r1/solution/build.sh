#!/usr/bin/env bash
# Build the linreg launcher: resolve the (stdlib-only) environment and
# precompile the package into a project-local depot so ./app starts fast.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"

export JULIA_DEPOT_PATH="$ROOT/.depot:"
export JULIA_PKG_OFFLINE=true

julia --project="$ROOT" --startup-file=no -O3 -e '
    using Linreg
'

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export JULIA_DEPOT_PATH="$ROOT/.depot:"
exec julia --project="$ROOT" --startup-file=no --history-file=no -O3 \
    -e 'using Linreg; exit(Linreg.main())'
LAUNCHER
chmod +x app
