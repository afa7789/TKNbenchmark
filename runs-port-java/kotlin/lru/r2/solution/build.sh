#!/usr/bin/env bash
# Builds the LRU simulator into build/lru.jar and creates the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc $(find src/main/kotlin -name '*.kt') -include-runtime -jvm-target 21 -d build/lru.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -jar "$DIR/build/lru.jar" "$@"
LAUNCHER
chmod +x app
