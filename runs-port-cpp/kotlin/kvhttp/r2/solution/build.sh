#!/usr/bin/env bash
# Builds an optimized release jar and a launcher script at ./app.
set -euo pipefail
cd "$(dirname "$0")"

command -v kotlinc >/dev/null 2>&1 || { echo "kotlinc not found on PATH" >&2; exit 1; }
command -v java >/dev/null 2>&1 || { echo "java not found on PATH" >&2; exit 1; }

mkdir -p build
kotlinc src/main/kotlin -include-runtime -jvm-target 21 -Werror -d build/kvhttp.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xshare:auto -cp "$DIR/build/kvhttp.jar" kvhttp.MainKt "$@"
LAUNCHER
chmod +x app
