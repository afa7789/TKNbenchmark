#!/usr/bin/env bash
# Build: install the R script as ./app (an Rscript launcher).
set -euo pipefail
cd "$(dirname "$0")"
Rscript -e 'invisible(parse("src/linreg.R"))'
cat > app <<'LAUNCH'
#!/usr/bin/env bash
exec Rscript --vanilla "$(dirname "$0")/src/linreg.R" "$@"
LAUNCH
chmod +x app
