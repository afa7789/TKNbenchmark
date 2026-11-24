#!/usr/bin/env bash
# Builds ./app: a launcher that runs linalg.R with Rscript.
set -euo pipefail
cd "$(dirname "$0")"
command -v Rscript >/dev/null || { echo "Rscript not found" >&2; exit 1; }
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec Rscript --vanilla "$(dirname "$0")/linalg.R" "$@"
LAUNCHER
chmod +x app
