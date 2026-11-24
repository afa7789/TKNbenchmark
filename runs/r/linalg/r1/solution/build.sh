#!/usr/bin/env bash
# Produce ./app: a launcher that runs the R implementation with Rscript.
set -euo pipefail
cd "$(dirname "$0")"
command -v Rscript >/dev/null || { echo "Rscript not found" >&2; exit 1; }
Rscript -e 'invisible(parse("src/linalg.R"))'
cat > app <<'LAUNCH'
#!/usr/bin/env bash
exec Rscript --vanilla "$(dirname "$0")/src/linalg.R" "$@"
LAUNCH
chmod +x app
