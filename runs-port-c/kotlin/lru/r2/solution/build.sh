#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
kotlinc src/Main.kt -include-runtime -nowarn -d build/lru.jar
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -jar "$(dirname "$0")/build/lru.jar" "$@"
LAUNCHER
chmod +x app
