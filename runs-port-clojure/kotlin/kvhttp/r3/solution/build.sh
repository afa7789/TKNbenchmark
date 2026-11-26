#!/usr/bin/env bash
# Builds a self-contained jar (Kotlin runtime included) and a launcher script at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target
mkdir -p target
kotlinc src/main/kotlin -include-runtime -jvm-target 21 -d target/kvhttp.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss512k -Xshare:auto \
  -jar "$DIR/target/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
