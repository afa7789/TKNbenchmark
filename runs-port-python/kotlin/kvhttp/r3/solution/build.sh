#!/usr/bin/env bash
# Builds ./app: a launcher for the kvhttp server jar (Kotlin stdlib + JDK only).
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc src/main/kotlin -jvm-target 21 -include-runtime -nowarn -d build/kvhttp.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -jar "$DIR/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
