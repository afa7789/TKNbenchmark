#!/usr/bin/env bash
# Creates ./app, a launcher that runs linalg.m with octave-cli.
set -euo pipefail
cd "$(dirname "$0")"
cat > app <<'SH'
#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
exec octave-cli -q -f --no-window-system "$here/linalg.m"
SH
chmod +x app
