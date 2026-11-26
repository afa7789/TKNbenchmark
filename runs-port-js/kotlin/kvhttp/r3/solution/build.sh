#!/usr/bin/env bash
# Builds ./app: a launcher that runs the kvhttp server jar on the JVM.
# Uses only the Kotlin standard library and the JDK (com.sun.net.httpserver).
set -euo pipefail
cd "$(dirname "$0")"

command -v kotlinc >/dev/null || { echo "build.sh: kotlinc is required" >&2; exit 1; }
command -v java >/dev/null || { echo "build.sh: java is required" >&2; exit 1; }

mkdir -p build
kotlinc src/main/kotlin -include-runtime -jvm-target 21 -d build/kvhttp.jar 2>&1 | grep -v '^warning: unable to find kotlin-stdlib' || true
[ -f build/kvhttp.jar ] || { echo "build.sh: compilation failed" >&2; exit 1; }

# Class-data-sharing archive for fast startup; created by a short training run.
rm -f build/kvhttp.jsa
java -XX:ArchiveClassesAtExit=build/kvhttp.jsa -cp build/kvhttp.jar kvhttp.MainKt 2>/dev/null || true

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDS=()
[ -f "$DIR/build/kvhttp.jsa" ] && CDS=(-XX:SharedArchiveFile="$DIR/build/kvhttp.jsa" -Xshare:auto)
exec java "${CDS[@]}" -XX:+UseSerialGC -Xss512k -cp "$DIR/build/kvhttp.jar" kvhttp.MainKt "$@"
LAUNCHER
chmod +x app
