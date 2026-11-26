#!/usr/bin/env bash
# Builds ./app: a launcher that runs the compiled Kotlin jar on the JVM.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/Main.kt -include-runtime -nowarn -d build/wordfreq.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -jar "$(dirname "$0")/build/wordfreq.jar" "$@"
LAUNCHER
chmod +x app
