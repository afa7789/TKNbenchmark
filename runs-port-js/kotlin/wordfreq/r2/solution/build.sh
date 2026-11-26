#!/usr/bin/env bash
# Builds ./app: a launcher that runs the wordfreq program on the JVM.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
rm -f build/wordfreq.jar
kotlinc src/main/kotlin/*.kt -include-runtime -d build/wordfreq.jar 2>&1 | grep -v '^warning:' || true
test -f build/wordfreq.jar

# Class-data-sharing archive to cut JVM startup time (best effort).
rm -f build/wordfreq.jsa
printf 'Warm up the CDS archive.\n' | java -XX:ArchiveClassesAtExit=build/wordfreq.jsa -XX:+UseSerialGC \
  -cp build/wordfreq.jar wordfreq.WordFreqKt >/dev/null 2>&1 || rm -f build/wordfreq.jsa

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
cds=()
[[ -f "$dir/build/wordfreq.jsa" ]] && cds=(-XX:SharedArchiveFile="$dir/build/wordfreq.jsa" -Xshare:auto)
exec java -XX:+UseSerialGC "${cds[@]}" -cp "$dir/build/wordfreq.jar" wordfreq.WordFreqKt "$@"
LAUNCHER
chmod +x app
