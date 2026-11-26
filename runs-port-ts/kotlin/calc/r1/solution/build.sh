#!/usr/bin/env bash
# Builds ./app: compiles the Kotlin sources into a self-contained jar, creates
# a class-data-sharing archive for fast JVM startup, and installs a launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc src/Main.kt -include-runtime -jvm-target 21 -d build/calc.jar 2>&1 | grep -v '^warning:' || true
[ -f build/calc.jar ] || { echo "compilation failed" >&2; exit 1; }

JVM_OPTS=(-XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss8m)

# Warm up once to record the loaded classes into a CDS archive (best effort).
printf '1 + 2 * 3\n(4 - 5) %% 2\nx\n' \
  | java "${JVM_OPTS[@]}" -XX:ArchiveClassesAtExit=build/calc.jsa -jar build/calc.jar >/dev/null 2>&1 \
  || rm -f build/calc.jsa

cat > app <<'LAUNCHER'
#!/bin/sh
dir="$(cd "$(dirname "$0")" && pwd)"
cds=""
[ -f "$dir/build/calc.jsa" ] && cds="-XX:SharedArchiveFile=$dir/build/calc.jsa -Xlog:cds=off -Xlog:cds+dynamic=off"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss8m $cds -jar "$dir/build/calc.jar" "$@"
LAUNCHER
chmod +x app
