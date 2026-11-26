#!/usr/bin/env bash
# Builds an optimized release jar and a launcher script at ./app.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/main/kotlin -jvm-target 21 -include-runtime -nowarn -d build/app.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"
exec "$JAVA" -jar "$DIR/build/app.jar" "$@"
LAUNCHER
chmod +x app
