#!/usr/bin/env bash
# Build the release jar and the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/WordFreq.kt -include-runtime -nowarn -d build/wordfreq.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -Xshare:auto -cp "$(dirname "$0")/build/wordfreq.jar" wordfreq.WordFreqKt "$@"
LAUNCHER
chmod +x app
