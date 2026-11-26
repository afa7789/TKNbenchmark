#!/usr/bin/env bash
# Builds a self-contained jar (Kotlin runtime included) and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/main/kotlin -jvm-target 21 -include-runtime -d build/kvhttp.jar 2>&1 | grep -v '^warning: unable to find kotlin-stdlib.jar' || true
test -s build/kvhttp.jar

# Class-data-sharing archive for faster JVM startup (best effort).
rm -f build/kvhttp.jsa
java -XX:ArchiveClassesAtExit=build/kvhttp.jsa -cp build/kvhttp.jar kvhttp.MainKt >/dev/null 2>&1 || true

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
cds=()
[[ -f "$dir/build/kvhttp.jsa" ]] && cds=(-XX:SharedArchiveFile="$dir/build/kvhttp.jsa" -Xshare:auto)
exec java "${cds[@]}" -XX:+UseSerialGC -Xss512k -cp "$dir/build/kvhttp.jar" kvhttp.MainKt "$@"
LAUNCHER
chmod +x app
