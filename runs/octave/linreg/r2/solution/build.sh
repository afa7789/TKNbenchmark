#!/usr/bin/env bash
# Builds ./app: a launcher that runs the Octave implementation in src/.
set -euo pipefail
cd "$(dirname "$0")"
command -v octave >/dev/null || { echo "octave not found in PATH" >&2; exit 1; }
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
exec octave --no-gui --no-window-system --quiet --norc --no-history \
  --path "$here/src" --eval "linreg"
LAUNCHER
chmod +x app
