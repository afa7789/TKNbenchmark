#!/usr/bin/env bash
# Compile the Kotlin sources into a self-contained jar and install the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
kotlinc src/*.kt -include-runtime -nowarn -d build/lru.jar
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -cp "$(dirname "$0")/build/lru.jar" LruKt "$@"
LAUNCHER
chmod +x app
