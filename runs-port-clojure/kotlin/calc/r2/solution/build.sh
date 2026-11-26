#!/usr/bin/env bash
# Builds a self-contained jar at build/calc.jar and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc src/main/kotlin -include-runtime -d build/calc.jar 2>&1 | grep -v '^warning:' || true
test -f build/calc.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xshare:auto -jar "$DIR/build/calc.jar" "$@"
LAUNCHER
chmod +x app
