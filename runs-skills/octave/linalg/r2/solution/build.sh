#!/usr/bin/env bash
# Build: generate the ./app launcher that runs linalg.m with octave-cli.
set -euo pipefail
cd "$(dirname "$0")"
command -v octave-cli >/dev/null || { echo "build.sh: octave-cli not found" >&2; exit 1; }
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec octave-cli -q -f --no-window-system -p "$dir" --eval "linalg ()"
LAUNCHER
chmod +x app
