#!/usr/bin/env bash
# Build: generate the ./app launcher that runs linalg.m with octave-cli.
set -euo pipefail
cd "$(dirname "$0")"
OCTAVE="$(command -v octave-cli || command -v octave)"
cat > app <<LAUNCH
#!/usr/bin/env bash
exec "$OCTAVE" --no-gui --norc --quiet --no-history "\$(dirname "\$0")/linalg.m"
LAUNCH
chmod +x app
