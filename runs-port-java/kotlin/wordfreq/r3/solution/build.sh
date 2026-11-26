#!/usr/bin/env bash
# Builds wordfreq into build/wordfreq.jar and installs the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc $(find src/main/kotlin -name '*.kt') -include-runtime -jvm-target 21 -d build/wordfreq.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -jar "$DIR/build/wordfreq.jar" "$@"
LAUNCHER
chmod +x app
