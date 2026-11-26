#!/usr/bin/env bash
# Builds the calc application into build/ and installs the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
cp src/*.ts build/

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$dir/build/main.ts"
LAUNCHER
chmod +x app
