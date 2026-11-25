#!/usr/bin/env bash
# Builds ./app: a launcher that runs the Octave implementation in src/.
set -euo pipefail
cd "$(dirname "$0")"
command -v octave-cli >/dev/null || { echo "build.sh: octave-cli not found" >&2; exit 1; }
cat > app <<'LAUNCH'
#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
exec octave-cli -q -f --no-window-system -p "$here/src" --eval "linalg_main ()"
LAUNCH
chmod +x app
