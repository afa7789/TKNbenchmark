#!/usr/bin/env bash
# Builds ./app: a launcher script for the kvhttp server jar (no third-party dependencies).
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc src/main/kotlin -jvm-target 21 -include-runtime -d build/kvhttp.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -Xshare:auto \
  -jar "$(dirname "$0")/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
