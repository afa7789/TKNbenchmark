#!/usr/bin/env bash
# Builds the kvhttp server into build/kvhttp.jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc -jvm-target 21 -include-runtime -d build/kvhttp.jar $(find src/main/kotlin -name '*.kt')

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -Xss512k -Xshare:auto -jar "$DIR/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
