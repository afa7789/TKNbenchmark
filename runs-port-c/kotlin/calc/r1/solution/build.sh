#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build
mkdir -p build
kotlinc src/main/kotlin/*.kt -include-runtime -d build/calc.jar
cat > app <<'SH'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -jar "$(dirname "$0")/build/calc.jar" "$@"
SH
chmod +x app
