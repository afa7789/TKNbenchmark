#!/usr/bin/env bash
# Builds build/calc.jar from the Kotlin sources and writes ./app, a launcher that runs it.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/*.kt -include-runtime -nowarn -d build/calc.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss16m -jar "$(dirname "$0")/build/calc.jar" "$@"
LAUNCHER
chmod +x app
