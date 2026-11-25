#!/usr/bin/env bash
# Builds ./app: a launcher that runs linalg.R with Rscript.
set -euo pipefail
cd "$(dirname "$0")"
Rscript --vanilla -e 'invisible(parse("linalg.R"))'
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec Rscript --vanilla "$(dirname "$0")/linalg.R" "$@"
LAUNCHER
chmod +x app
