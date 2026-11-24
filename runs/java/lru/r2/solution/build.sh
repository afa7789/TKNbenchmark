#!/usr/bin/env bash
# Builds the LRU simulator into build/lru.jar and creates the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 21 -O -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/lru.jar --main-class lru.Main -C build/classes .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -jar "$DIR/build/lru.jar" "$@"
LAUNCHER
chmod +x app
