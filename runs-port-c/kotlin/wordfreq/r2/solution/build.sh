#!/usr/bin/env bash
# Builds the Kotlin sources into build/wordfreq.jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc src/*.kt -include-runtime -d build/wordfreq.jar 2>&1 | grep -v '^warning:' || true
test -f build/wordfreq.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -Xss8m -Xms256m -Xmx2g -Xshare:auto \
    -cp "$(dirname "$0")/build/wordfreq.jar" wordfreq.MainKt "$@"
LAUNCHER
chmod +x app
