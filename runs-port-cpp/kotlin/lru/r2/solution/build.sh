#!/usr/bin/env bash
# Builds the Kotlin sources into a self-contained jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build app
mkdir -p build
kotlinc src/*.kt -include-runtime -nowarn -d build/app.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xms256m -jar "$(dirname "$0")/build/app.jar" "$@"
LAUNCHER
chmod +x app
