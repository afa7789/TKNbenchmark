#!/usr/bin/env bash
# Builds the LRU cache simulator and installs a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 21 -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/lru.jar --main-class lru.Main -C build/classes .

# Class-data sharing archive for faster JVM startup (best effort).
java -XX:ArchiveClassesAtExit=build/lru.jsa -jar build/lru.jar <<< $'1\nSET a 1\nGET a\nDEL a\nSIZE' >/dev/null 2>&1 || rm -f build/lru.jsa

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
opts=(-XX:+UseSerialGC)
if [[ -f "$dir/build/lru.jsa" ]]; then
  opts+=(-XX:SharedArchiveFile="$dir/build/lru.jsa" -Xlog:cds=off -Xlog:cds+dynamic=off)
fi
exec java "${opts[@]}" -jar "$dir/build/lru.jar" "$@"
LAUNCHER
chmod +x app
