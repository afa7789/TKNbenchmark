#!/usr/bin/env bash
# Builds the release jar and the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
kotlinc src/*.kt -include-runtime -nowarn -d build/calc.jar
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss16m -cp "$(dirname "$0")/build/calc.jar" calc.CalcKt "$@"
LAUNCHER
chmod +x app
