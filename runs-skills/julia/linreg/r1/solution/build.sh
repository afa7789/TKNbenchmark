#!/usr/bin/env bash
# Instantiate and precompile the LinReg package, then install the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

JULIA_FLAGS=(--startup-file=no -O3 --project=.)

julia "${JULIA_FLAGS[@]}" -e 'using Pkg; Pkg.instantiate(); Pkg.precompile(); using LinReg'

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec julia --startup-file=no -O3 --project="$DIR" -e 'using LinReg; exit(LinReg.main())'
LAUNCHER
chmod +x app
