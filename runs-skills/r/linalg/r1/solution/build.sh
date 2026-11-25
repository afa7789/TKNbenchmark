#!/usr/bin/env bash
# Build ./app: a launcher that runs src/linalg.R with Rscript.
set -euo pipefail
cd "$(dirname "$0")"
command -v Rscript >/dev/null || { echo "Rscript not found" >&2; exit 1; }
Rscript --vanilla -e 'invisible(parse("src/linalg.R"))'
cat > app <<'LAUNCH'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec Rscript --vanilla "$dir/src/linalg.R" "$@"
LAUNCH
chmod +x app
