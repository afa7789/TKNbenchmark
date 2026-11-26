#!/usr/bin/env bash
# Produces ./app: a launcher that runs the calculator jar on the JVM.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/*.kt -include-runtime -nowarn -d build/calc.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss8m -jar "$(dirname "$0")/build/calc.jar" "$@"
LAUNCHER
chmod +x app
