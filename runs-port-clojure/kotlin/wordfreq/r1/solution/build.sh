#!/usr/bin/env bash
# Builds a self-contained jar (Kotlin runtime included) and a ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target app
mkdir -p target

kotlinc src/*.kt -include-runtime -jvm-target 21 -d target/wordfreq.jar 2>&1 | grep -v '^warning:' || true
test -f target/wordfreq.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto \
  -cp "${dir}/target/wordfreq.jar" wordfreq.WordFreqKt "$@"
LAUNCHER
chmod +x app
