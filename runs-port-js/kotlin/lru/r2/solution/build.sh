#!/usr/bin/env bash
# Builds the Kotlin LRU simulator into build/lru.jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
kotlinc src/main/kotlin -include-runtime -jvm-target 21 -nowarn -d build/lru.jar
# Class-data-sharing archive to cut JVM startup time (best effort).
java -XX:ArchiveClassesAtExit=build/lru.jsa -jar build/lru.jar <<< $'1\nSET a 1\nGET a\nDEL a\nSIZE' > /dev/null 2>&1 || rm -f build/lru.jsa
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
cds=()
[[ -f "$dir/build/lru.jsa" ]] && cds=(-XX:SharedArchiveFile="$dir/build/lru.jsa" -Xshare:auto)
exec java -XX:+UseSerialGC -XX:+TieredCompilation -Xss16m "${cds[@]}" -jar "$dir/build/lru.jar" "$@"
LAUNCHER
chmod +x app
