#!/usr/bin/env bash
# Builds a self-contained jar (Kotlin runtime included) and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build app
mkdir -p build

kotlinc src/calc/Main.kt -include-runtime -jvm-target 21 -d build/calc.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto \
  -jar "$DIR/build/calc.jar" "$@"
LAUNCHER
chmod +x app
