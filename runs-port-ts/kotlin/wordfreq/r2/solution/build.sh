#!/usr/bin/env bash
# Builds a self-contained jar (Kotlin runtime included) and a ./app launcher for it.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/Main.kt -include-runtime -d build/wordfreq.jar

cat > app <<'LAUNCHER'
#!/bin/sh
exec java -XX:+UseSerialGC -jar "$(dirname "$0")/build/wordfreq.jar" "$@"
LAUNCHER
chmod +x app
