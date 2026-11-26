#!/usr/bin/env bash
# Builds ./app: a launcher that runs the kvhttp server jar on the JVM.
set -euo pipefail
cd "$(dirname "$0")"
command -v kotlinc >/dev/null || { echo "kotlinc is required" >&2; exit 1; }
command -v java >/dev/null || { echo "java is required" >&2; exit 1; }

rm -rf build
mkdir -p build
kotlinc src/main/kotlin -jvm-target 21 -include-runtime -d build/kvhttp.jar 2>&1 | grep -v '^warning: unable to find kotlin-stdlib' || true
[ -f build/kvhttp.jar ] || { echo "compilation failed" >&2; exit 1; }

# Pre-build a class-data-sharing archive so the server starts quickly.
java -XX:ArchiveClassesAtExit=build/kvhttp.jsa -cp build/kvhttp.jar kvhttp.MainKt 2>/dev/null || true

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
cds=()
[ -f "$dir/build/kvhttp.jsa" ] && cds=(-XX:SharedArchiveFile="$dir/build/kvhttp.jsa" -Xshare:auto)
exec java "${cds[@]}" -XX:+UseSerialGC -Xss512k -cp "$dir/build/kvhttp.jar" kvhttp.MainKt "$@"
LAUNCHER
chmod +x app
