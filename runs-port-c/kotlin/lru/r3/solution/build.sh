#!/usr/bin/env bash
# Builds the Kotlin LRU simulator into build/lru.jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build app
mkdir -p build
kotlinc src/Lru.kt -include-runtime -nowarn -d build/lru.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -jar "$DIR/build/lru.jar" "$@"
LAUNCHER
chmod +x app
