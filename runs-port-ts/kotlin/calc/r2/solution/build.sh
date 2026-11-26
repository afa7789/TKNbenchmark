#!/usr/bin/env bash
# Builds a self-contained jar (Kotlin runtime included) and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/main/kotlin -include-runtime -jvm-target 21 -nowarn -d build/calc.jar

cat > app <<'LAUNCHER'
#!/bin/sh
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss8m -cp "$dir/build/calc.jar" calc.MainKt "$@"
LAUNCHER
chmod +x app
