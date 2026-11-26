#!/usr/bin/env bash
# Builds the release jar and the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/main/kotlin -include-runtime -nowarn -d build/wordfreq.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -jar "$(dirname "$0")/build/wordfreq.jar" "$@"
LAUNCHER
chmod +x app
