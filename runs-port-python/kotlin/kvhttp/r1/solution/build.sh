#!/usr/bin/env bash
# Build kvhttp: compile the Kotlin sources into a self-contained jar and install the ./app launcher.
# Uses only the Kotlin and Java standard libraries, so there is nothing to fetch.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src -include-runtime -d build/kvhttp.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -jar "$HERE/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
