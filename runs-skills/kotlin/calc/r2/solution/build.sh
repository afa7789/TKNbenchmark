#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build && mkdir -p build
kotlinc src/Main.kt -jvm-target 21 -include-runtime -d build/app.jar 2>&1 | grep -v '^warning' || true
test -f build/app.jar
cat > app <<'LAUNCH'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss8m -jar "$(dirname "$0")/build/app.jar" "$@"
LAUNCH
chmod +x app
