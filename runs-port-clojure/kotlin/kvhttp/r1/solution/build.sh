#!/usr/bin/env bash
# Compiles the server into a self-contained jar and writes a ./app launcher for it.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target
mkdir -p target
kotlinc src/main/kotlin -jvm-target 21 -include-runtime -d target/kvhttp.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -jar "$DIR/target/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
