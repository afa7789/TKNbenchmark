#!/usr/bin/env bash
# Builds the wordfreq jar and writes ./app, a launcher that runs it on the JVM.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build app
mkdir -p build
kotlinc src/Main.kt -include-runtime -nowarn -d build/wordfreq.jar

cat > app <<'SH'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -Xshare:auto -jar "$(dirname "$0")/build/wordfreq.jar"
SH
chmod +x app
