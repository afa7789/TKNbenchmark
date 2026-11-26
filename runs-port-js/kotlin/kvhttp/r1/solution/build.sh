#!/usr/bin/env bash
# Builds ./app: a launcher that runs the kvhttp server jar on the JVM.
# Uses only the JDK and the Kotlin standard library (bundled into the jar).
set -euo pipefail
cd "$(dirname "$0")"

command -v kotlinc >/dev/null || { echo "kotlinc is required" >&2; exit 1; }
command -v java >/dev/null || { echo "java is required" >&2; exit 1; }

rm -rf build
mkdir -p build
kotlinc src/main/kotlin -include-runtime -jvm-target 21 -d build/kvhttp.jar 2>&1 | grep -v '^warning: ' || true
[[ -f build/kvhttp.jar ]] || { echo "compilation failed" >&2; exit 1; }

# Class-data sharing archive for faster startup (best effort).
java -XX:ArchiveClassesAtExit=build/kvhttp.jsa -jar build/kvhttp.jar 2>/dev/null || true

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDS=()
[[ -f "$DIR/build/kvhttp.jsa" ]] && CDS=(-XX:SharedArchiveFile="$DIR/build/kvhttp.jsa" -Xshare:auto)
exec java "${CDS[@]}" -XX:+UseSerialGC -Xss512k -jar "$DIR/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
