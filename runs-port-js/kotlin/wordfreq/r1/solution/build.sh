#!/usr/bin/env bash
# Produce ./app: a launcher that runs the compiled wordfreq jar on the JVM.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build && mkdir -p build
kotlinc src/WordFreq.kt -include-runtime -d build/wordfreq.jar 2>&1 | grep -v '^warning:' || true
test -f build/wordfreq.jar
cat > app <<'LAUNCHER'
#!/bin/sh
exec java -XX:+UseSerialGC -Xshare:auto -cp "$(dirname "$0")/build/wordfreq.jar" wordfreq.WordFreqKt "$@"
LAUNCHER
chmod +x app
