#!/usr/bin/env bash
# Build the wordfreq jar and its launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/WordFreq.kt -include-runtime -nowarn -d build/wordfreq.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -jar "$(dirname "$0")/build/wordfreq.jar" "$@"
LAUNCHER
chmod +x app
