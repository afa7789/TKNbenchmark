#!/usr/bin/env bash
# Compiles the Kotlin sources into a self-contained jar and writes ./app, a launcher for it.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/*.kt -include-runtime -nowarn -d build/app.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xss16m -XX:+UseCompressedOops -Xshare:auto -jar "$DIR/build/app.jar" "$@"
LAUNCHER
chmod +x app
