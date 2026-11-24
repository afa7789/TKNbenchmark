#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build && mkdir -p build
kotlinc src/*.kt -include-runtime -d build/app.jar 2>&1 | grep -v '^warning:' || true
test -f build/app.jar
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -Xshare:auto -jar "$(dirname "$0")/build/app.jar" "$@"
LAUNCHER
chmod +x app
