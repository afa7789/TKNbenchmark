#!/usr/bin/env bash
# Build: install a launcher at ./app that runs linreg.m with octave-cli.
set -euo pipefail
cd "$(dirname "$0")"
command -v octave-cli >/dev/null || { echo "build.sh: octave-cli not found" >&2; exit 1; }
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec octave-cli -q -f --no-window-system "$dir/linreg.m"
LAUNCHER
chmod +x app
