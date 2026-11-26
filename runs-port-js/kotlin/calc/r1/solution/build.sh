#!/usr/bin/env bash
# Builds build/calc.jar (with the Kotlin runtime bundled), a class-data-sharing
# archive for faster JVM startup, and ./app: a launcher that runs the jar.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc src/calc/*.kt -include-runtime -jvm-target 21 -d build/calc.jar 2>&1 | grep -v '^warning:' || true
[[ -f build/calc.jar ]] || { echo "compilation failed" >&2; exit 1; }

JVM_OPTS=(-XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto)

# Record the classes loaded by a training run into a CDS archive (best effort).
printf '1 + 2 * 3\n-(4 %% 3) / 0\n(1\n\n' |
  java "${JVM_OPTS[@]}" -XX:ArchiveClassesAtExit=build/calc.jsa -jar build/calc.jar >/dev/null 2>&1 ||
  rm -f build/calc.jsa

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
cds=()
[[ -f "$dir/build/calc.jsa" ]] && cds=(-XX:SharedArchiveFile="$dir/build/calc.jsa")
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto "${cds[@]}" -jar "$dir/build/calc.jar" "$@"
LAUNCHER
chmod +x app
