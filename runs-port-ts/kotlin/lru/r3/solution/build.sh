#!/usr/bin/env bash
# Compiles the Kotlin sources into a self-contained jar and writes ./app, a launcher for it.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/*.kt -include-runtime -nowarn -d build/lru.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseParallelGC -Xms256m -Xmx2g -cp "$DIR/build/lru.jar" lru.MainKt "$@"
LAUNCHER
chmod +x app
