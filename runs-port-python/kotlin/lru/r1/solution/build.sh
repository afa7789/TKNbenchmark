#!/usr/bin/env bash
# Build: compile the Kotlin sources into a self-contained jar and install the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/main/kotlin -include-runtime -nowarn -d build/lru.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
# Launcher for the LRU cache simulator.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -Xss8m -jar "$here/build/lru.jar"
LAUNCHER
chmod +x app
