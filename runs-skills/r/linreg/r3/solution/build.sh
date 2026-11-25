#!/usr/bin/env bash
# Build the release launcher at ./app (R is interpreted; nothing to compile).
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'LAUNCH'
#!/usr/bin/env bash
exec Rscript --vanilla "$(dirname "$0")/linreg.R"
LAUNCH
chmod +x app
