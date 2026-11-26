#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build && mkdir -p build
kotlinc src/Main.kt -include-runtime -d build/calc.jar 2>&1 | grep -v '^warning:' || true
test -f build/calc.jar
cat > app <<'SH'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss8m -jar "$DIR/build/calc.jar"
SH
chmod +x app
