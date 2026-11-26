#!/usr/bin/env bash
# Builds the calculator into build/app.jar and produces ./app, a launcher that runs it on the JVM.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc src/main/kotlin -include-runtime -jvm-target 21 -nowarn -d build/app.jar
[ -f build/app.jar ] || { echo "compilation failed" >&2; exit 1; }

JVM_OPTS='-XX:+UseSerialGC -XX:TieredStopAtLevel=1'

# Class-data-sharing archive to cut JVM startup time (optional; skipped if unsupported).
CDS_OPTS=''
if printf '1 + 2 * 3\n(1\n-4 %% 3\n' \
    | java $JVM_OPTS -XX:ArchiveClassesAtExit=build/app.jsa -jar build/app.jar >/dev/null 2>&1 \
    && [ -f build/app.jsa ]; then
  CDS_OPTS='-XX:SharedArchiveFile="$DIR/build/app.jsa" -Xlog:cds=off -Xlog:cds+dynamic=off'
fi

cat > app <<LAUNCHER
#!/bin/sh
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
exec java $JVM_OPTS $CDS_OPTS -jar "\$DIR/build/app.jar"
LAUNCHER
chmod +x app
