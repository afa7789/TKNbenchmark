#!/usr/bin/env bash
# Produces ./app, a launcher that runs linreg.R with Rscript.
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'LAUNCH'
#!/usr/bin/env bash
exec Rscript --vanilla "$(dirname "$0")/linreg.R" "$@"
LAUNCH
chmod +x app
