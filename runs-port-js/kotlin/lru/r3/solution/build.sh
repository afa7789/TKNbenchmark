#!/usr/bin/env bash
# Builds the LRU simulator into build/lru.jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
kotlinc src/main/kotlin/*.kt -include-runtime -nowarn -d build/lru.jar
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -jar "$(dirname "$0")/build/lru.jar" "$@"
LAUNCHER
chmod +x app
