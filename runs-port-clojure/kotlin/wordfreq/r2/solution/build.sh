#!/usr/bin/env bash
# Compiles the Kotlin sources into a self-contained jar at build/wordfreq.jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build

kotlinc src/main/kotlin -include-runtime -jvm-target 21 -d build/wordfreq.jar

cat > app <<'LAUNCH'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xshare:auto \
  -cp "$dir/build/wordfreq.jar" wordfreq.WordFreqKt "$@"
LAUNCH
chmod +x app
