#!/usr/bin/env bash
# Produce ./app: a launcher that runs linalg.m with GNU Octave.
set -euo pipefail
cd "$(dirname "$0")"
command -v octave-cli >/dev/null 2>&1 || command -v octave >/dev/null 2>&1 || {
  echo "build.sh: GNU Octave not found" >&2; exit 1; }
cat > app <<'LAUNCH'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
oct="$(command -v octave-cli || command -v octave)"
exec "$oct" --no-gui --no-init-file --no-site-file --no-history --quiet \
  --eval "addpath('$dir'); try, linalg(); catch err, fprintf(2, '%s\n', err.message); exit(1); end"
LAUNCH
chmod +x app
