#!/usr/bin/env bash
# Builds the wordfreq release jar and the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/*.kt -include-runtime -nowarn -d build/wordfreq.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -cp "$(dirname "$0")/build/wordfreq.jar" wordfreq.WordFreqKt "$@"
LAUNCHER
chmod +x app
