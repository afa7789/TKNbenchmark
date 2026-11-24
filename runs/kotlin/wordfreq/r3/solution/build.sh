#!/usr/bin/env bash
# Builds the release jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build
mkdir -p build
kotlinc src/Main.kt -include-runtime -nowarn -d build/app.jar
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -Xss16m -jar "$DIR/build/app.jar"
LAUNCHER
chmod +x app
