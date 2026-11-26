#!/usr/bin/env bash
# Builds a self-contained jar (Kotlin runtime included) and a ./app launcher for it.
# Requires kotlinc and a JDK 21+ on PATH; there are no third-party dependencies.
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
exec java -XX:+UseSerialGC -jar "$DIR/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
