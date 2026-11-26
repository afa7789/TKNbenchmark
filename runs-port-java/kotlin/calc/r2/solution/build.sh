#!/usr/bin/env bash
# Builds the calculator into build/calc.jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc src -include-runtime -jvm-target 21 -d build/calc.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -cp "$DIR/build/calc.jar" calc.MainKt "$@"
LAUNCHER
chmod +x app
