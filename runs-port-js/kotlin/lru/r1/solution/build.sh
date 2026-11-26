#!/usr/bin/env bash
# Builds the LRU simulator into build/lru.jar and writes ./app, a launcher that runs it.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc src/*.kt -include-runtime -d build/lru.jar 2>&1 | grep -v '^warning:' || true
test -f build/lru.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -Xms256m -cp "$dir/build/lru.jar" MainKt "$@"
LAUNCHER
chmod +x app
