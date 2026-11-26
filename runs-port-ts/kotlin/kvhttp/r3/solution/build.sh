#!/usr/bin/env bash
# Builds ./app: a launcher that runs the compiled Kotlin server jar on the JVM.
set -euo pipefail
cd "$(dirname "$0")"

command -v kotlinc >/dev/null || { echo "kotlinc is required" >&2; exit 1; }
command -v java >/dev/null || { echo "java is required" >&2; exit 1; }

rm -rf build
mkdir -p build
kotlinc src/main/kotlin -include-runtime -jvm-target 21 -nowarn -d build/kvhttp.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -XX:+ExitOnOutOfMemoryError -jar "$DIR/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
