#!/usr/bin/env bash
# Build ./app: a launcher that runs the R implementation with Rscript.
set -euo pipefail
cd "$(dirname "$0")"
command -v Rscript >/dev/null || { echo "Rscript not found" >&2; exit 1; }
# Fail the build early if the source does not parse.
Rscript --vanilla -e 'invisible(parse("R/linreg.R"))'
cat > app <<'LAUNCH'
#!/usr/bin/env bash
exec Rscript --vanilla --default-packages=base,stats "$(dirname "$0")/R/linreg.R" "$@"
LAUNCH
chmod +x app
