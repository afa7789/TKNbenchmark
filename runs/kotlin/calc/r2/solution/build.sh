#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build && mkdir -p build
kotlinc src/Main.kt -include-runtime -d build/calc.jar 2>&1 | grep -v '^warning' || true
test -f build/calc.jar
cat > app <<'SH'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -Xshare:auto -jar "$(dirname "$0")/build/calc.jar" "$@"
SH
chmod +x app
