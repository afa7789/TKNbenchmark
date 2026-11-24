#!/usr/bin/env bash
# Builds a self-contained jar (Kotlin runtime included) and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc src/main/kotlin -include-runtime -jvm-target 21 -d build/kvhttp.jar 2>&1 | grep -v '^warning:' || true
test -f build/kvhttp.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -Xss512k -jar "$DIR/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
