#!/usr/bin/env bash
# Builds calc into build/calc.jar and installs the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc $(find src/main/kotlin -name '*.kt') -include-runtime -jvm-target 21 -d build/calc.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xshare:auto -cp "$DIR/build/calc.jar" calc.MainKt "$@"
LAUNCHER
chmod +x app
