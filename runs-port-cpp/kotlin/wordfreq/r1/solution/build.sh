#!/usr/bin/env bash
# Builds a self-contained jar (Kotlin runtime included) and a ./app launcher that runs it.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/*.kt -include-runtime -nowarn -d build/wordfreq.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -cp "$(dirname "$0")/build/wordfreq.jar" wordfreq.MainKt "$@"
LAUNCHER
chmod +x app
