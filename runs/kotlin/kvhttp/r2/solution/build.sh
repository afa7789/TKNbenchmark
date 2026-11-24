#!/usr/bin/env bash
# Builds a self-contained jar (with the Kotlin runtime) and an ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
rm -f build/kvhttp.jar
kotlinc src/main/kotlin -include-runtime -jvm-target 21 -d build/kvhttp.jar 2>&1 | grep -v '^warning' || true
[ -f build/kvhttp.jar ] || { echo "build failed" >&2; exit 1; }

cat > app <<'LAUNCH'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -Xss512k -Dsun.net.httpserver.nodelay=true \
  -jar "$DIR/build/kvhttp.jar" "$@"
LAUNCH
chmod +x app
