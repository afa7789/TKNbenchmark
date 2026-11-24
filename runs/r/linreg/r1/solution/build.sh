#!/usr/bin/env bash
# Produces ./app: a launcher that runs the R implementation via Rscript.
set -euo pipefail
cd "$(dirname "$0")"
command -v Rscript >/dev/null || { echo "Rscript not found" >&2; exit 1; }
Rscript -e 'invisible(parse("src/linreg.R"))'
cat > app <<'LAUNCH'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec Rscript --vanilla --default-packages=base,stats "$dir/src/linreg.R"
LAUNCH
chmod +x app
