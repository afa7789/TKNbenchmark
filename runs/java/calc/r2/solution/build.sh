#!/usr/bin/env bash
# Builds the calculator into build/calc.jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 21 -d build/classes $(find src -name '*.java')
jar --create --file build/calc.jar --main-class calc.Main -C build/classes .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -jar "$DIR/build/calc.jar" "$@"
LAUNCHER
chmod +x app
