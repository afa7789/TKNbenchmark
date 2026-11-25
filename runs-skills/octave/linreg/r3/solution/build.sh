#!/usr/bin/env bash
# Produce ./app: a launcher that runs the Octave implementation in src/.
set -euo pipefail
cd "$(dirname "$0")"
command -v octave-cli >/dev/null || { echo "build.sh: octave-cli not found" >&2; exit 1; }
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
exec octave-cli -q -f --no-window-system "$here/src/linreg.m"
LAUNCHER
chmod +x app
