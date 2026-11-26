#!/usr/bin/env bash
# Compiles the server into a self-contained jar and writes a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc src -jvm-target 21 -include-runtime -d build/kvhttp.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -Xshare:auto -jar "$DIR/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
