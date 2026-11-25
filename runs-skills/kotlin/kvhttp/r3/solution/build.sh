#!/usr/bin/env bash
# Builds the kvhttp server into build/kvhttp.jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build && mkdir -p build
kotlinc src/main/kotlin -jvm-target 21 -include-runtime -d build/kvhttp.jar 2>&1 | grep -v '^warning' || true
[[ -f build/kvhttp.jar ]] || { echo "build failed" >&2; exit 1; }

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -cp "$DIR/build/kvhttp.jar" kvhttp.MainKt "$@"
LAUNCHER
chmod +x app
