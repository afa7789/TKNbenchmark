#!/usr/bin/env bash
# Compiles the Kotlin sources into build/app.jar and installs the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc -nowarn -include-runtime -d build/app.jar $(find src/main/kotlin -name '*.kt')

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xshare:auto -jar "$DIR/build/app.jar" "$@"
LAUNCHER
chmod +x app
