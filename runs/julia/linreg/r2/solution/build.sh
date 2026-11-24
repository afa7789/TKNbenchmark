#!/usr/bin/env bash
# Precompile the LinReg package into a project-local depot and install ./app.
set -euo pipefail
cd "$(dirname "$0")"

export JULIA_DEPOT_PATH="$PWD/.julia-depot:"
export JULIA_PROJECT="$PWD/LinReg"

julia --startup-file=no -O3 -e 'using Pkg; Pkg.instantiate(); using LinReg'

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export JULIA_DEPOT_PATH="$DIR/.julia-depot:"
export JULIA_PROJECT="$DIR/LinReg"
exec julia --startup-file=no -O3 --history-file=no -e 'using LinReg; exit(LinReg.main())'
LAUNCHER
chmod +x app
