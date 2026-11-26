#!/usr/bin/env bash
# Build a release jar and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/*.kt -include-runtime -nowarn -d build/lru.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -XX:+TieredCompilation -Xshare:auto -jar "$DIR/build/lru.jar" "$@"
LAUNCHER
chmod +x app
