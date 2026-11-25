#!/usr/bin/env bash
# Builds build/kvhttp.jar and the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}"
rm -rf build
mkdir -p build/classes
"${JAVA_BIN}javac" --release 27 -Xlint:all -Werror -d build/classes $(find src/main/java -name '*.java')
"${JAVA_BIN}jar" --create --file build/kvhttp.jar --main-class kvhttp.Main -C build/classes .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"
exec "$JAVA" -XX:+UseSerialGC -jar "$DIR/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
