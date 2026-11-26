#!/usr/bin/env bash
# Builds a self-contained release jar and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/main/kotlin -include-runtime -jvm-target 21 -nowarn -d build/kvhttp.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -Xshare:auto -jar "$(dirname "$0")/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
