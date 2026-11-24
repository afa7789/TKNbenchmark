#!/usr/bin/env bash
# Builds ./app: a launcher that runs linreg.R with Rscript.
set -euo pipefail
cd "$(dirname "$0")"

command -v Rscript >/dev/null || { echo "Rscript not found" >&2; exit 1; }
Rscript -e 'invisible(parse("linreg.R"))'

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec Rscript --vanilla --default-packages=base "$here/linreg.R" "$@"
LAUNCHER
chmod +x app
