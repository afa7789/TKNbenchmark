#!/usr/bin/env bash
# Generates ./app, a launcher that runs src/linreg.m under octave-cli.
set -euo pipefail
cd "$(dirname "$0")"

command -v octave-cli >/dev/null || { echo "octave-cli not found" >&2; exit 1; }

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
exec octave-cli --no-init-file --no-site-file --no-history --quiet \
  --path "$here/src" --eval "linreg"
LAUNCHER
chmod +x app
